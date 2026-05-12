// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import "./IMoonpotManager.sol";
import "./IMoonpotHook.sol";
import "./MoonpotToken.sol";

contract MoonpotHook is BaseHook, Ownable, ReentrancyGuard, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    uint8 private constant ACTION_INJECT_LIQUIDITY = 0;

    IPositionManager public immutable posm;
    IPermit2 public immutable permit2;
    IERC20 public immutable usdc;
    IERC20 public immutable tmp;

    address public manager;
    bool private _initialized;

    PoolKey public poolKey;
    int24 public currentFloorTick;

    uint256 public _positionId;
    int24 public floorTickLower;
    int24 public floorTickUpper;

    uint24 public baseDefenseTax = 3_000;
    uint24 public maxDefenseTax = 500_000;
    int24 public taxRampTicks = 4080;

    int24 public positionTickLower;
    int24 public positionTickUpper;

    uint128 public protocolLiquidity;

    error InvalidAddress();
    error InvalidDefenseParams();
    error InvalidTokens();
    error ManagerNotSet();
    error ManagerAlreadySet();
    error OnlyManager();
    error PoolAlreadyInitialized();
    error ExactOutputTMPSellBlocked();
    error InvalidTickBound();

    event CurrentFloorTickUpdated(int24 tick);
    event DefenseParamsUpdated(
        uint24 baseTax,
        uint24 maxTax,
        int24 taxRampTicks
    );
    event PositionIdSet(uint256 id);
    event ManagerSet(address manager);
    event FeesHarvested(uint256 usdcAmount, uint256 tmpAmount);
    event TMPIntercepted(uint256 tmpBurned, uint256 maxAllowed);

    modifier onlyManager() {
        if (manager == address(0)) revert ManagerNotSet();
        if (msg.sender != manager) revert OnlyManager();
        _;
    }

    constructor(
        IPoolManager _poolManager,
        address _posm,
        address _permit2,
        address _usdc,
        address _tmp,
        address _owner
    ) BaseHook(_poolManager) Ownable(_owner) {
        if (
            _posm == address(0) ||
            _permit2 == address(0) ||
            _usdc == address(0) ||
            _tmp == address(0)
        ) revert InvalidAddress();

        posm = IPositionManager(_posm);
        permit2 = IPermit2(_permit2);
        usdc = IERC20(_usdc);
        tmp = IERC20(_tmp);

        usdc.approve(_permit2, type(uint256).max);
        tmp.approve(_permit2, type(uint256).max);
        IPermit2(_permit2).approve(
            address(usdc),
            address(posm),
            type(uint160).max,
            type(uint48).max
        );
        IPermit2(_permit2).approve(
            address(tmp),
            address(posm),
            type(uint160).max,
            type(uint48).max
        );
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal override returns (bytes4) {
        if (
            Currency.unwrap(key.currency0) != address(usdc) &&
            Currency.unwrap(key.currency1) != address(usdc)
        ) revert InvalidTokens();

        if (_initialized) revert PoolAlreadyInitialized();

        poolKey = key;
        _initialized = true;

        return BaseHook.beforeInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (PoolId.unwrap(key.toId()) != PoolId.unwrap(poolKey.toId()))
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);

        bool usdcIsCurrency0 = Currency.unwrap(key.currency0) == address(usdc);
        bool isSellingTMP = usdcIsCurrency0
            ? !params.zeroForOne
            : params.zeroForOne;

        if (!isSellingTMP)
            return (
                BaseHook.beforeSwap.selector,
                toBeforeSwapDelta(0, 0),
                baseDefenseTax | LPFeeLibrary.DYNAMIC_FEE_FLAG
            );
        if (params.amountSpecified > 0) revert ExactOutputTMPSellBlocked();

        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(
            key.toId()
        );

        int24 ticksAboveFloor = currentTick - currentFloorTick;
        uint24 tax = _calculateTax(ticksAboveFloor);

        uint24 feeWithFlag = tax > 0
            ? (tax | LPFeeLibrary.DYNAMIC_FEE_FLAG)
            : 0;

        uint256 swapAmount = uint256(-params.amountSpecified);
        uint256 maxTmpSell = _computeMaxTmpSell(usdcIsCurrency0, sqrtPriceX96);

        if (swapAmount <= maxTmpSell)
            return (
                BaseHook.beforeSwap.selector,
                toBeforeSwapDelta(0, 0),
                feeWithFlag
            );

        uint256 excessTmp = swapAmount - maxTmpSell;
        Currency tmpCurrency = usdcIsCurrency0 ? key.currency1 : key.currency0;

        poolManager.take(tmpCurrency, address(this), excessTmp);
        MoonpotToken(address(tmp)).burn(excessTmp);

        emit TMPIntercepted(excessTmp, maxTmpSell);

        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(int256(excessTmp)), 0),
            feeWithFlag
        );
    }

    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        uint8 action = abi.decode(data[:32], (uint8));

        if (action == ACTION_INJECT_LIQUIDITY) {
            (, uint256 usdcAmount) = abi.decode(data, (uint8, uint256));

            bool usdcIsZero = Currency.unwrap(poolKey.currency0) ==
                address(usdc);

            int24 tickLower = positionTickLower;
            int24 tickUpper = positionTickUpper;

            (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolKey.toId());

            uint256 MAX_V4_AMOUNT = uint256(uint128(type(int128).max));

            uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                usdcIsZero ? usdcAmount : MAX_V4_AMOUNT,
                usdcIsZero ? MAX_V4_AMOUNT : usdcAmount
            );

            if (liquidityToAdd > 0) {
                bytes memory actions = abi.encodePacked(
                    uint8(Actions.INCREASE_LIQUIDITY),
                    uint8(Actions.SETTLE_PAIR)
                );
                bytes[] memory p = new bytes[](2);
                p[0] = abi.encode(
                    _positionId,
                    liquidityToAdd,
                    MAX_V4_AMOUNT,
                    MAX_V4_AMOUNT,
                    bytes("")
                );
                p[1] = abi.encode(poolKey.currency0, poolKey.currency1);

                posm.modifyLiquiditiesWithoutUnlock(actions, p);

                protocolLiquidity += liquidityToAdd;
            }

            uint256 leftover = tmp.balanceOf(address(this));
            if (leftover > 0) MoonpotToken(address(tmp)).burn(leftover);
        }

        return bytes("");
    }

    function injectLiquidity(
        uint256 usdcAmount
    ) external onlyManager nonReentrant {
        if (usdcAmount == 0) return;
        poolManager.unlock(abi.encode(ACTION_INJECT_LIQUIDITY, usdcAmount));
    }

    function quoteSell(
        uint256 tmpAmount
    )
        external
        view
        returns (uint256 effectiveSell, uint256 tmpBurned, uint24 tax)
    {
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(
            poolKey.toId()
        );
        bool usdcIsCurrency0 = Currency.unwrap(poolKey.currency0) ==
            address(usdc);

        uint256 maxSell = _computeMaxTmpSell(usdcIsCurrency0, sqrtPriceX96);

        if (tmpAmount <= maxSell) {
            effectiveSell = tmpAmount;
            tmpBurned = 0;
        } else {
            effectiveSell = maxSell;
            tmpBurned = tmpAmount - maxSell;
        }

        int24 ticksAboveFloor = currentTick - currentFloorTick;
        tax = _calculateTax(ticksAboveFloor);
    }

    function quoteBuy(
        uint256 usdcAmount
    ) external view returns (uint256 tmpOut, uint24 tax) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolKey.toId());
        uint128 liquidity = poolManager.getLiquidity(poolKey.toId());
        bool usdcIsCurrency0 = Currency.unwrap(poolKey.currency0) ==
            address(usdc);

        tax = baseDefenseTax;

        if (liquidity == 0 || sqrtPriceX96 == 0) return (0, tax);

        uint256 amountInAfterFee = FullMath.mulDiv(
            usdcAmount,
            uint256(1_000_000 - tax),
            1_000_000
        );

        if (usdcIsCurrency0) {
            uint256 liquidityQ96 = uint256(liquidity) << 96;
            uint256 denominator = liquidityQ96 +
                FullMath.mulDiv(
                    amountInAfterFee,
                    sqrtPriceX96,
                    FixedPoint96.Q96
                );

            if (denominator == 0) return (0, tax);

            uint160 sqrtPriceNew = uint160(
                FullMath.mulDiv(liquidityQ96, sqrtPriceX96, denominator)
            );

            if (sqrtPriceNew >= sqrtPriceX96) return (0, tax);

            tmpOut = FullMath.mulDiv(
                liquidity,
                sqrtPriceX96 - sqrtPriceNew,
                FixedPoint96.Q96
            );
        } else {
            uint256 sqrtPriceDelta = FullMath.mulDiv(
                amountInAfterFee,
                FixedPoint96.Q96,
                liquidity
            );
            uint160 sqrtPriceNew = uint160(
                uint256(sqrtPriceX96) + sqrtPriceDelta
            );

            tmpOut = FullMath.mulDiv(
                FullMath.mulDiv(liquidity, sqrtPriceDelta, sqrtPriceNew),
                FixedPoint96.Q96,
                sqrtPriceX96
            );
        }
    }

    function harvestFees() external nonReentrant onlyOwner {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            _positionId,
            uint128(0),
            uint128(0),
            uint128(0),
            ""
        );
        params[1] = abi.encode(
            poolKey.currency0,
            poolKey.currency1,
            address(this)
        );

        posm.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 15 minutes
        );

        uint256 pending = IMoonpotManager(manager).pendingLiquidityUsdc();
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 usdcFees = usdcBalance > pending ? usdcBalance - pending : 0;

        if (usdcFees > 0) {
            usdc.safeTransfer(IMoonpotManager(manager).company(), usdcFees);
        }

        uint256 tmpFees = tmp.balanceOf(address(this));

        if (tmpFees > 0) {
            MoonpotToken(address(tmp)).burn(tmpFees);
        }

        if (usdcFees > 0 || tmpFees > 0) {
            emit FeesHarvested(usdcFees, tmpFees);
        }
    }

    function _calculateTax(
        int24 ticksAboveFloor
    ) internal view returns (uint24 tax) {
        if (ticksAboveFloor <= 0) return maxDefenseTax;
        if (ticksAboveFloor >= taxRampTicks) return baseDefenseTax;

        uint256 reduction = (uint256(uint24(maxDefenseTax - baseDefenseTax)) *
            uint256(uint24(ticksAboveFloor))) / uint256(uint24(taxRampTicks));

        tax = uint24(maxDefenseTax - uint24(reduction));
    }

    function _computeMaxTmpSell(
        bool usdcIsCurrency0,
        uint160 sqrtPriceX96
    ) internal view returns (uint256 maxTmpSell) {
        uint128 liquidity = protocolLiquidity;
        if (liquidity == 0) return 0;

        if (usdcIsCurrency0) {
            uint160 sqrtFloorUpper = TickMath.getSqrtPriceAtTick(
                floorTickUpper
            );

            if (sqrtPriceX96 >= sqrtFloorUpper) return 0;

            maxTmpSell = FullMath.mulDiv(
                liquidity,
                sqrtFloorUpper - sqrtPriceX96,
                FixedPoint96.Q96
            );
        } else {
            uint160 sqrtFloorLower = TickMath.getSqrtPriceAtTick(
                floorTickLower
            );

            if (sqrtPriceX96 <= sqrtFloorLower) return 0;

            maxTmpSell = FullMath.mulDiv(
                FullMath.mulDiv(liquidity, FixedPoint96.Q96, sqrtFloorLower),
                sqrtPriceX96 - sqrtFloorLower,
                sqrtPriceX96
            );
        }
    }

    function setPositionId(
        uint256 id,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external onlyManager {
        if (id == 0) return;

        _positionId = id;
        positionTickLower = tickLower;
        positionTickUpper = tickUpper;
        protocolLiquidity = liquidity;

        emit PositionIdSet(id);
    }

    function setCurrentFloorTick(int24 tick) external onlyManager {
        currentFloorTick = tick;
        floorTickLower = tick - poolKey.tickSpacing;
        floorTickUpper = tick + poolKey.tickSpacing;

        emit CurrentFloorTickUpdated(tick);
    }

    function setManager(address _manager) external onlyOwner {
        if (_manager == address(0)) revert InvalidAddress();
        if (manager != address(0)) revert ManagerAlreadySet();

        manager = _manager;

        emit ManagerSet(_manager);
    }

    function setDefenseParams(
        uint24 _base,
        uint24 _max,
        int24 _taxRampTicks
    ) external onlyOwner {
        if (_base > _max) revert InvalidDefenseParams();
        if (_taxRampTicks <= 0) revert InvalidDefenseParams();
        if (_max > 1_000_000) revert InvalidDefenseParams();

        baseDefenseTax = _base;
        maxDefenseTax = _max;
        taxRampTicks = _taxRampTicks;

        emit DefenseParamsUpdated(_base, _max, _taxRampTicks);
    }

    function positionId() external view returns (uint256) {
        return _positionId;
    }
}
