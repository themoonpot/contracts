// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMoonpotRound {
    enum Class {
        None,
        Class1,
        Class2,
        Class3,
        Class4,
        Class5,
        Class6,
        Class7,
        Class8,
        Class9,
        Class10,
        Class11,
        Class12,
        Class13,
        Class14,
        Class15,
        Class16
    }

    struct NFTClass {
        Class classId;
        uint128 usdcValue;
    }

    function getRoundId() external view returns (uint256);

    function getPricePerToken() external view returns (uint256);

    function getCompanyShare() external view returns (uint256);

    function getCommunityShare() external view returns (uint256);

    function getLiquidityShare() external view returns (uint256);

    function getTokenCount() external view returns (uint256);

    function getTokensSold() external view returns (uint256);

    function getNFTCount() external view returns (uint32);

    function getNFTsMinted() external view returns (uint32);

    function getStartTime() external view returns (uint256);

    function getEndTime() external view returns (uint256);

    function getScannedCount() external view returns (uint256);

    function getSeedRequestId() external view returns (uint256);

    function getSeed() external view returns (uint256);

    function getNFTClass(uint32 index) external view returns (NFTClass memory);

    function notifyPurchase(uint256 tokenAmount) external;

    function notifyScanned(uint256 scannedCount) external;

    function notifyNFTMinted(uint32 nftCount) external;

    function start() external;

    function end() external;

    function setSeedRequestId(uint256 requestId) external;

    function setSeed(uint256 seed) external;

    function depositFunds(uint256 amount) external;

    function releaseReward(address recipient, uint256 amount) external;

    function permute(
        uint256 index,
        uint256 seed
    ) external view returns (uint256);

    function valueOf(
        uint256 tokenId
    ) external view returns (uint256 value, uint8 classId, uint32 drawId);
}
