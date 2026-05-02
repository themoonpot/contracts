// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolInitializer_v4} from "@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";

import "./IMoonpotHook.sol";
import "./IMoonpotManager.sol";
import "./IMoonpotRound.sol";
import "./MoonpotNFT.sol";
import "./MoonpotToken.sol";

contract MoonpotManager is
    ReentrancyGuard,
    VRFConsumerBaseV2Plus,
    IMoonpotManager
{
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    struct Purchase {
        address buyer;
        uint256 tmpAmount;
        uint256 nftAmount;
        uint256 roundId;
        uint256 requestTimestamp;
        uint256 seed;
        uint256 soldBefore;
        uint32 nftsMintedBefore;
        bool isDrawn;
        bool isFilled;
    }

    enum VRFRequestType {
        None,
        Purchase,
        Round
    }

    IERC20 public immutable usdc;
    MoonpotNFT public immutable nft;
    MoonpotToken public immutable tmp;
    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    IPermit2 public immutable permit2;
    address public immutable hook;

    PoolKey public poolKey;
    uint256 public pendingLiquidityUsdc;
    mapping(uint256 => uint256) public lastInjectionCheckpoint;

    uint24 lpFee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
    int24 tickSpacing = 60;

    int24 public constant INIT_TICK_PREMIUM = 1_200;
    uint256 public constant MAX_PURCHASE_LIMIT = 10_000;
    uint256 public constant VRF_TIMEOUT = 24 hours;
    uint8 public constant MAX_ROUNDS = 28;

    address public _company;
    uint256 public _currentRoundId;

    bytes32 public vrfKeyHash;
    uint256 public vrfSubId;
    uint32 public vrfCallbackGasLimit = 200_000;
    uint16 public vrfConfirmations = 3;

    mapping(uint256 => IMoonpotRound) public rounds;
    mapping(uint256 => Purchase) public purchases;
    mapping(uint256 => mapping(uint256 => bool)) public claimed;
    mapping(uint256 => VRFRequestType) public vrfRequestType;
    mapping(uint256 => uint256) public vrfToId;

    bool public isInitialized;
    uint256 public lastPurchaseId;
    uint256 public tokensSold;
    uint256 public nftsMinted;

    event RoundSet(uint256 indexed roundId, address roundAddress);
    event RoundStarted(uint256 indexed roundId, uint256 timestamp);
    event RoundEnded(uint256 indexed roundId, uint256 timestamp);
    event RoundRevealed(uint256 indexed roundId, uint256 seed);
    event RoundRevealRetried(uint256 indexed roundId, uint256 requestId);
    event PurchaseCommitted(
        uint256 indexed roundId,
        uint256 indexed purchaseId,
        address indexed buyer,
        uint256 amount
    );
    event PurchaseSeedDrawn(
        uint256 indexed roundId,
        uint256 indexed purchaseId,
        address indexed buyer,
        uint256 seed
    );
    event PurchaseFilled(
        uint256 indexed roundId,
        uint256 indexed purchaseId,
        address indexed buyer,
        uint256 nftAmount
    );
    event PurchaseReDrawn(uint256 indexed purchaseId, uint256 newRequestId);
    event NFTClaimed(
        uint256 indexed roundId,
        uint256 indexed tokenId,
        uint8 classId,
        uint256 usdcValue
    );
    event CompanySet(address company);
    event VRFParamsSet(
        bytes32 keyHash,
        uint256 subId,
        uint256 callbackGasLimit
    );
    event PendingLiquidityUpdated(uint256 newPending);

    error AlreadyClaimed();
    error AlreadyFilled();
    error AlreadyInitialized();
    error AlreadySeeded();
    error HookNotSet();
    error IncorrectAmount();
    error InvalidAddress();
    error InvalidNFTCount();
    error InvalidScannedCount();
    error InvalidTickBound();
    error MaxPurchaseLimitExceeded();
    error NotInitialized();
    error NotOwner();
    error RetryTooEarly();
    error RoundActive();
    error RoundOutOfBounds();
    error RoundExists();
    error RoundMissing();
    error RoundNotActive();
    error RoundNotEnded();
    error RoundNotSeeded();
    error RoundSoldOut();
    error SeedNotDrawn();
    error TokenSupplyNotEnough();

    constructor(
        address _usdc,
        address _tmp,
        address _nft,
        address _comp,
        address _vrf,
        bytes32 _key,
        uint256 _sub,
        address _poolm,
        address _posm,
        address _permit2,
        address _hook
    ) VRFConsumerBaseV2Plus(_vrf) {
        if (
            _usdc == address(0) ||
            _tmp == address(0) ||
            _nft == address(0) ||
            _comp == address(0) ||
            _vrf == address(0) ||
            _poolm == address(0) ||
            _posm == address(0) ||
            _permit2 == address(0) ||
            _hook == address(0)
        ) revert InvalidAddress();

        usdc = IERC20(_usdc);
        tmp = MoonpotToken(_tmp);
        nft = MoonpotNFT(_nft);
        _company = _comp;
        vrfKeyHash = _key;
        vrfSubId = _sub;
        poolManager = IPoolManager(_poolm);
        positionManager = IPositionManager(_posm);
        permit2 = IPermit2(_permit2);
        hook = _hook;
    }

    function init(uint256 usdcAmount, int24 ceilingTick) external onlyOwner {
        if (address(hook) == address(0)) revert HookNotSet();
        if (isInitialized) revert AlreadyInitialized();
        if (ceilingTick == 0) revert InvalidTickBound();
        if (address(rounds[1]) == address(0)) revert RoundMissing();

        uint256 firstRoundPrice = rounds[1].getPricePerToken();
        int24 floorTick = _calculateTickFromPrice(firstRoundPrice);

        bool usdcIsToken0 = address(usdc) < address(tmp);

        int24 tickLower = usdcIsToken0 ? ceilingTick : floorTick - tickSpacing;
        int24 tickUpper = usdcIsToken0 ? floorTick + tickSpacing : ceilingTick;

        int24 initTick;
        {
            int24 raw = usdcIsToken0
                ? floorTick - INIT_TICK_PREMIUM
                : floorTick + INIT_TICK_PREMIUM;
            int24 remainder = raw % tickSpacing;
            initTick = remainder < 0
                ? raw - (tickSpacing + remainder)
                : raw - remainder;
        }

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(initTick);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liquidity;
        uint256 tmpNeeded;

        if (usdcIsToken0) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(
                sqrtPriceX96,
                sqrtUpper,
                usdcAmount
            );
            tmpNeeded = FullMath.mulDiv(
                uint256(liquidity),
                uint256(sqrtPriceX96) - uint256(sqrtLower),
                FixedPoint96.Q96
            );
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(
                sqrtLower,
                sqrtPriceX96,
                usdcAmount
            );
            tmpNeeded =
                FullMath.mulDiv(
                    uint256(liquidity) << 96,
                    uint256(sqrtUpper) - uint256(sqrtPriceX96),
                    uint256(sqrtUpper)
                ) /
                uint256(sqrtPriceX96);
        }

        uint256 tmpToMint = (tmpNeeded * 101) / 100 + 1;
        tmp.mint(address(this), tmpToMint);

        address t0 = address(usdc) < address(tmp)
            ? address(usdc)
            : address(tmp);
        address t1 = address(usdc) < address(tmp)
            ? address(tmp)
            : address(usdc);

        poolKey = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });

        usdc.approve(address(permit2), usdcAmount);
        tmp.approve(address(permit2), tmpToMint);
        permit2.approve(
            address(usdc),
            address(positionManager),
            uint160(usdcAmount),
            uint48(block.timestamp + 1 days)
        );
        permit2.approve(
            address(tmp),
            address(positionManager),
            uint160(tmpToMint),
            uint48(block.timestamp + 1 days)
        );

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encodeWithSelector(
            IPoolInitializer_v4.initializePool.selector,
            poolKey,
            sqrtPriceX96
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );
        bytes[] memory mintParams = new bytes[](2);
        mintParams[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,
            t0 == address(usdc) ? usdcAmount : tmpToMint,
            t0 == address(usdc) ? tmpToMint : usdcAmount,
            hook,
            bytes("")
        );
        mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            block.timestamp + 15 minutes
        );
        positionManager.multicall(params);

        uint256 leftover = tmp.balanceOf(address(this));
        if (leftover > 0) MoonpotToken(address(tmp)).burn(leftover);

        uint256 newPositionId = positionManager.nextTokenId() - 1;

        IMoonpotHook(hook).setPositionId(
            newPositionId,
            usdcIsToken0 ? tickUpper : tickLower,
            usdcIsToken0 ? tickLower : tickUpper,
            liquidity
        );

        isInitialized = true;
    }

    function start() external onlyOwner {
        if (!isInitialized) revert NotInitialized();

        if (_currentRoundId == 0) {
            if (address(rounds[1]) == address(0)) revert RoundMissing();

            _currentRoundId = 1;
            rounds[1].start();
            emit RoundStarted(1, block.timestamp);

            uint256 price = rounds[1].getPricePerToken();
            int24 floorTick = _calculateTickFromPrice(price);
            IMoonpotHook(hook).setCurrentFloorTick(floorTick);

            return;
        }

        IMoonpotRound current = rounds[_currentRoundId];
        if (current.getEndTime() == 0) revert RoundActive();

        uint256 nextId = _currentRoundId + 1;
        if (nextId > MAX_ROUNDS) revert RoundOutOfBounds();
        if (address(rounds[nextId]) == address(0)) revert RoundMissing();

        _currentRoundId = nextId;
        rounds[nextId].start();

        int24 newFloorTick = _calculateTickFromPrice(
            rounds[nextId].getPricePerToken()
        );
        IMoonpotHook(hook).setCurrentFloorTick(newFloorTick);

        emit RoundStarted(nextId, block.timestamp);
    }

    function setRound(uint256 id, address addr) external onlyOwner {
        if (id == 0 || id > MAX_ROUNDS) revert RoundOutOfBounds();
        if (address(rounds[id]) != address(0)) revert RoundExists();
        if (addr == address(0)) revert InvalidAddress();

        rounds[id] = IMoonpotRound(addr);
        emit RoundSet(id, addr);
    }

    function buyFor(
        address buyer,
        uint256 usdcAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        _validateRound();

        IMoonpotRound round = rounds[_currentRoundId];
        uint256 price = round.getPricePerToken();
        uint256 soldBefore = round.getTokensSold();

        if (usdcAmount < price || usdcAmount % price != 0)
            revert IncorrectAmount();

        uint256 requestedTokens = usdcAmount / price;
        if (requestedTokens > MAX_PURCHASE_LIMIT)
            revert MaxPurchaseLimitExceeded();

        uint256 available = round.getTokenCount() - soldBefore;
        if (available == 0) revert RoundSoldOut();
        if (requestedTokens > available) revert TokenSupplyNotEnough();

        if (usdc.allowance(buyer, address(this)) < usdcAmount) {
            try
                IERC20Permit(address(usdc)).permit(
                    buyer,
                    address(this),
                    usdcAmount,
                    deadline,
                    v,
                    r,
                    s
                )
            {} catch {}
        }

        usdc.safeTransferFrom(buyer, address(this), usdcAmount);
        usdc.safeTransfer(_company, requestedTokens * round.getCompanyShare());

        uint256 communityAmount = requestedTokens * round.getCommunityShare();
        usdc.safeTransfer(address(round), communityAmount);
        round.depositFunds(communityAmount);

        tmp.mint(buyer, requestedTokens * 1e18);
        round.notifyPurchase(requestedTokens);
        tokensSold += requestedTokens;

        uint256 liquidityShare = requestedTokens * round.getLiquidityShare();
        usdc.safeTransfer(hook, liquidityShare);
        pendingLiquidityUsdc += liquidityShare;
        emit PendingLiquidityUpdated(pendingLiquidityUsdc);

        uint256 reqId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubId,
                requestConfirmations: vrfConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        uint256 purchaseId = ++lastPurchaseId;
        purchases[purchaseId] = Purchase({
            buyer: buyer,
            tmpAmount: requestedTokens,
            nftAmount: 0,
            roundId: _currentRoundId,
            requestTimestamp: block.timestamp,
            seed: 0,
            soldBefore: soldBefore,
            nftsMintedBefore: round.getNFTsMinted(),
            isDrawn: false,
            isFilled: false
        });

        vrfRequestType[reqId] = VRFRequestType.Purchase;
        vrfToId[reqId] = purchaseId;

        emit PurchaseCommitted(
            _currentRoundId,
            purchaseId,
            buyer,
            requestedTokens
        );

        _maybeInjectLiquidity();
        _maybeEndRound();
    }

    function processBuy(uint256 purchaseId) external nonReentrant {
        Purchase storage p = purchases[purchaseId];
        IMoonpotRound round = rounds[p.roundId];

        if (p.buyer == address(0)) revert InvalidAddress();
        if (!p.isDrawn) revert SeedNotDrawn();
        if (p.isFilled) revert AlreadyFilled();

        uint256 drawsLeft = round.getTokenCount() - p.soldBefore;
        uint32 nftsLeft = round.getNFTCount() - p.nftsMintedBefore;
        uint256 nftsFound = 0;

        if (nftsLeft > 0 && drawsLeft > 0) {
            for (uint256 i = 0; i < p.tmpAmount; i++) {
                if (nftsLeft == 0) break;

                uint256 check = uint256(keccak256(abi.encodePacked(p.seed, i)));

                if ((check % drawsLeft) < nftsLeft) {
                    nftsFound++;
                    nftsLeft--;
                }

                drawsLeft--;
            }

            if (nftsFound > 0) {
                nft.mintTo(p.buyer, nftsFound, p.roundId);
                round.notifyNFTMinted(uint32(nftsFound));
                nftsMinted += nftsFound;
            }
        }

        p.isFilled = true;
        p.nftAmount = nftsFound;

        round.notifyScanned(p.tmpAmount);
        emit PurchaseFilled(p.roundId, purchaseId, p.buyer, nftsFound);
    }

    function claimNFT(uint256 tokenId) external nonReentrant {
        if (nft.ownerOf(tokenId) != msg.sender) revert NotOwner();

        uint256 roundId = nft.getRound(tokenId);
        if (roundId == 0) revert InvalidAddress();

        IMoonpotRound round = rounds[roundId];

        if (address(round) == address(0)) revert InvalidAddress();
        if (round.getEndTime() == 0) revert RoundNotEnded();
        if (round.getSeed() == 0) revert RoundNotSeeded();
        if (claimed[roundId][tokenId]) revert AlreadyClaimed();

        (uint256 value, uint8 classId, ) = round.valueOf(tokenId);

        claimed[roundId][tokenId] = true;
        round.releaseReward(msg.sender, value);

        emit NFTClaimed(roundId, tokenId, classId, value);
    }

    function claimNFTs(uint256[] calldata tokenIds) external nonReentrant {
        if (tokenIds.length == 0) return;

        uint256 lastRoundId = 0;
        uint256 roundTotal = 0;
        IMoonpotRound currentRound;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            if (nft.ownerOf(tokenId) != msg.sender) revert NotOwner();

            uint256 roundId = nft.getRound(tokenId);
            if (roundId == 0) revert InvalidAddress();

            if (roundId != lastRoundId) {
                if (roundTotal > 0) {
                    currentRound.releaseReward(msg.sender, roundTotal);
                }

                currentRound = rounds[roundId];
                if (address(currentRound) == address(0))
                    revert InvalidAddress();

                lastRoundId = roundId;
                roundTotal = 0;
            }

            if (currentRound.getEndTime() == 0) revert RoundNotEnded();
            if (currentRound.getSeed() == 0) revert RoundNotSeeded();
            if (claimed[roundId][tokenId]) revert AlreadyClaimed();

            (uint256 value, uint8 classId, ) = currentRound.valueOf(tokenId);

            claimed[roundId][tokenId] = true;
            roundTotal += value;

            emit NFTClaimed(roundId, tokenId, classId, value);
        }

        if (roundTotal > 0) {
            currentRound.releaseReward(msg.sender, roundTotal);
        }
    }

    function fulfillRandomWords(
        uint256 reqId,
        uint256[] calldata words
    ) internal override {
        VRFRequestType reqType = vrfRequestType[reqId];
        uint256 id = vrfToId[reqId];

        delete vrfRequestType[reqId];
        delete vrfToId[reqId];

        if (reqType == VRFRequestType.Round) {
            rounds[id].setSeed(words[0]);
            emit RoundRevealed(id, words[0]);
        } else if (reqType == VRFRequestType.Purchase) {
            Purchase storage p = purchases[id];
            if (p.buyer == address(0) || p.isDrawn) return;
            p.seed = words[0];
            p.isDrawn = true;
            emit PurchaseSeedDrawn(p.roundId, id, p.buyer, p.seed);
        }
    }

    function reDrawPurchase(uint256 purchaseId) external {
        Purchase storage p = purchases[purchaseId];

        if (p.buyer == address(0)) revert InvalidAddress();
        if (p.isDrawn) revert AlreadySeeded();

        if (
            block.timestamp < p.requestTimestamp + VRF_TIMEOUT &&
            msg.sender != owner()
        ) revert RetryTooEarly();

        uint256 reqId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubId,
                requestConfirmations: vrfConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        p.requestTimestamp = block.timestamp;

        vrfRequestType[reqId] = VRFRequestType.Purchase;
        vrfToId[reqId] = purchaseId;

        emit PurchaseReDrawn(purchaseId, reqId);
    }

    function retryRoundReveal(uint256 roundId) external onlyOwner {
        IMoonpotRound round = rounds[roundId];

        if (address(round) == address(0)) revert RoundMissing();
        if (round.getEndTime() == 0) revert RoundNotEnded();
        if (round.getSeed() != 0) revert AlreadyFilled();

        uint256 reqId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubId,
                requestConfirmations: vrfConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        vrfRequestType[reqId] = VRFRequestType.Round;
        vrfToId[reqId] = roundId;

        round.setSeedRequestId(reqId);
        emit RoundRevealRetried(roundId, reqId);
    }

    function setVRFParams(
        bytes32 keyHash,
        uint256 subId,
        uint32 callbackGasLimit
    ) external onlyOwner {
        vrfCallbackGasLimit = callbackGasLimit;
        vrfKeyHash = keyHash;
        vrfSubId = subId;
        emit VRFParamsSet(keyHash, subId, callbackGasLimit);
    }

    function setCompany(address newCompany) external onlyOwner {
        if (newCompany == address(0)) revert InvalidAddress();
        _company = newCompany;
        emit CompanySet(newCompany);
    }

    function currentRoundId() external view returns (uint256) {
        return _currentRoundId;
    }

    function company() external view returns (address) {
        return _company;
    }

    function _maybeInjectLiquidity() internal {
        IMoonpotRound round = rounds[_currentRoundId];
        uint256 roundTokenCount = round.getTokenCount();
        uint256 tokensSoldInRound = round.getTokensSold();
        uint256 checkpoint = lastInjectionCheckpoint[_currentRoundId];
        uint256 interval = roundTokenCount / 40;

        if (
            interval == 0 ||
            tokensSoldInRound / interval <= checkpoint / interval
        ) return;

        lastInjectionCheckpoint[_currentRoundId] = tokensSoldInRound;

        uint256 usdcAmount = pendingLiquidityUsdc;
        if (usdcAmount == 0) return;

        bool usdcIsToken0 = address(usdc) < address(tmp);
        int24 _positionTickLower = IMoonpotHook(hook).positionTickLower();
        int24 _positionTickUpper = IMoonpotHook(hook).positionTickUpper();

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolKey.toId());

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(_positionTickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(_positionTickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtLower,
            sqrtUpper,
            usdcIsToken0 ? usdcAmount : type(uint128).max,
            usdcIsToken0 ? type(uint128).max : usdcAmount
        );

        uint256 tmpAmount = 0;

        if (liquidity > 0) {
            if (usdcIsToken0) {
                uint160 sqrtUpperForAmount1 = sqrtPriceX96 < sqrtUpper
                    ? sqrtPriceX96
                    : sqrtUpper;
                if (sqrtUpperForAmount1 > sqrtLower) {
                    tmpAmount = _getAmount1ForLiquidity(
                        sqrtLower,
                        sqrtUpperForAmount1,
                        liquidity
                    );
                }
            } else {
                uint160 sqrtLowerForAmount0 = sqrtPriceX96 > sqrtLower
                    ? sqrtPriceX96
                    : sqrtLower;
                if (sqrtUpper > sqrtLowerForAmount0) {
                    tmpAmount = _getAmount0ForLiquidity(
                        sqrtLowerForAmount0,
                        sqrtUpper,
                        liquidity
                    );
                }
            }
        }

        tmpAmount = (tmpAmount * 101) / 100 + 1;
        tmp.mint(address(hook), tmpAmount);

        IMoonpotHook(hook).injectLiquidity(usdcAmount);
        pendingLiquidityUsdc = 0;
        emit PendingLiquidityUpdated(pendingLiquidityUsdc);
    }

    function _maybeEndRound() internal {
        if (_currentRoundId == 0) revert RoundMissing();

        IMoonpotRound round = rounds[_currentRoundId];
        if (round.getEndTime() != 0) return;
        if (round.getTokensSold() < round.getTokenCount()) return;

        round.end();
        emit RoundEnded(_currentRoundId, block.timestamp);

        uint256 reqId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubId,
                requestConfirmations: vrfConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        vrfRequestType[reqId] = VRFRequestType.Round;
        vrfToId[reqId] = _currentRoundId;

        round.setSeedRequestId(reqId);

        uint256 nextRoundId = _currentRoundId + 1;

        if (address(rounds[nextRoundId]) != address(0)) {
            IMoonpotRound nextRound = rounds[nextRoundId];
            uint256 newPrice = nextRound.getPricePerToken();
            int24 newFloorTick = _calculateTickFromPrice(newPrice);
            IMoonpotHook(hook).setCurrentFloorTick(newFloorTick);

            nextRound.start();
            _currentRoundId = nextRoundId;
            emit RoundStarted(nextRoundId, block.timestamp);
        }
    }

    function _validateRound() internal view {
        IMoonpotRound round = rounds[_currentRoundId];

        if (
            address(round) == address(0) ||
            block.timestamp < round.getStartTime() ||
            round.getEndTime() != 0
        ) revert RoundNotActive();
    }

    function _calculateTickFromPrice(
        uint256 priceUSDC
    ) internal view returns (int24 tick) {
        uint256 ratio = FullMath.mulDiv(priceUSDC, 1 << 192, 1e18);
        uint160 sqrtPriceX96 = uint160(Math.sqrt(ratio));
        int24 tickRaw = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        bool usdcIsToken0 = address(usdc) < address(tmp);
        tick = usdcIsToken0 ? -tickRaw : tickRaw;

        int24 remainder = tick % tickSpacing;
        tick = remainder < 0
            ? tick - (tickSpacing + remainder)
            : tick - remainder;
    }

    function _getAmount0ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        return
            FullMath.mulDiv(
                uint256(liquidity) << 96,
                sqrtPriceBX96 - sqrtPriceAX96,
                sqrtPriceBX96
            ) / sqrtPriceAX96;
    }

    function _getAmount1ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        return
            FullMath.mulDiv(
                uint256(liquidity),
                sqrtPriceBX96 - sqrtPriceAX96,
                FixedPoint96.Q96
            );
    }
}
