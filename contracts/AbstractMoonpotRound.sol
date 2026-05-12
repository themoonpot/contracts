// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IMoonpotRound.sol";

abstract contract AbstractMoonpotRound is IMoonpotRound {
    using SafeERC20 for IERC20;

    uint256 public immutable roundId;
    address public immutable manager;
    IERC20 public immutable usdc;

    uint256 public immutable PRICE;
    uint256 public immutable TOTAL_TOKENS;
    uint32 public immutable TOTAL_NFTS;

    uint256 public immutable SHARE_COMMUNITY;
    uint256 public immutable SHARE_COMPANY;
    uint256 public immutable SHARE_LIQUIDITY;

    uint256 public startTime = type(uint256).max;
    uint256 public endTime;
    uint256 public tokensSold;
    uint32 public nftsMinted;
    uint256 public rewardPool;
    uint256 public scannedCount;
    uint256 public seedRequestId;
    uint256 public seed;

    error InvalidAddress();
    error InvalidRoundId();
    error InvalidShareAmounts();
    error InsufficientFunds();
    error Unauthorized();

    constructor(
        uint256 _roundId,
        address _manager,
        address _usdc,
        uint256 _price,
        uint256 _tokens,
        uint32 _nfts,
        uint256 _sComm,
        uint256 _sComp,
        uint256 _sLiq
    ) {
        if (_manager == address(0) || _usdc == address(0))
            revert InvalidAddress();
        if (_roundId == 0) revert InvalidRoundId();
        if (_sComm + _sComp + _sLiq != _price) revert InvalidShareAmounts();

        roundId = _roundId;
        manager = _manager;
        usdc = IERC20(_usdc);
        PRICE = _price;
        TOTAL_TOKENS = _tokens;
        TOTAL_NFTS = _nfts;
        SHARE_COMMUNITY = _sComm;
        SHARE_COMPANY = _sComp;
        SHARE_LIQUIDITY = _sLiq;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Unauthorized();
        _;
    }

    function getRoundId() external view override returns (uint256) {
        return roundId;
    }

    function getPricePerToken() external view override returns (uint256) {
        return PRICE;
    }

    function getTokenCount() external view override returns (uint256) {
        return TOTAL_TOKENS;
    }

    function getNFTCount() external view override returns (uint32) {
        return TOTAL_NFTS;
    }

    function getCompanyShare() external view override returns (uint256) {
        return SHARE_COMPANY;
    }

    function getCommunityShare() external view override returns (uint256) {
        return SHARE_COMMUNITY;
    }

    function getLiquidityShare() external view override returns (uint256) {
        return SHARE_LIQUIDITY;
    }

    function getTokensSold() external view override returns (uint256) {
        return tokensSold;
    }

    function getNFTsMinted() external view override returns (uint32) {
        return nftsMinted;
    }

    function getScannedCount() external view override returns (uint256) {
        return scannedCount;
    }

    function getStartTime() external view override returns (uint256) {
        return startTime;
    }

    function getEndTime() external view override returns (uint256) {
        return endTime;
    }

    function getSeed() external view override returns (uint256) {
        return seed;
    }

    function getSeedRequestId() external view override returns (uint256) {
        return seedRequestId;
    }

    function start() external override onlyManager {
        startTime = block.timestamp;
    }

    function end() external override onlyManager {
        endTime = block.timestamp;
    }

    function notifyPurchase(uint256 amount) external override onlyManager {
        tokensSold += amount;
    }

    function notifyScanned(uint256 amount) external override onlyManager {
        scannedCount += amount;
    }

    function notifyNFTMinted(uint32 count) external override onlyManager {
        nftsMinted += count;
    }

    function setSeedRequestId(uint256 requestId) external override onlyManager {
        seedRequestId = requestId;
    }

    function setSeed(uint256 _seed) external override onlyManager {
        seed = _seed;
    }

    function depositFunds(uint256 amount) external override onlyManager {
        rewardPool += amount;
    }

    function releaseReward(
        address recipient,
        uint256 amount
    ) external override onlyManager {
        if (rewardPool < amount) revert InsufficientFunds();

        rewardPool -= amount;
        IERC20(usdc).safeTransfer(recipient, amount);
    }

    function getNFTClass(
        uint32 index
    ) external view virtual override returns (NFTClass memory);

    function permute(
        uint256 index,
        uint256 seed
    ) external view virtual override returns (uint256);

    function valueOf(
        uint256 tokenId
    ) external view returns (uint256 value, uint8 classId, uint32 drawId) {
        if (seed == 0) return (0, 0, 0);

        uint256 draw = this.permute(tokenId % TOTAL_TOKENS, seed);
        NFTClass memory nftClass = this.getNFTClass(uint32(draw));

        return (nftClass.usdcValue, uint8(nftClass.classId), uint32(draw));
    }
}
