// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "erc721a/contracts/ERC721A.sol";
import "erc721a/contracts/extensions/ERC721AQueryable.sol";

contract MoonpotNFT is ERC721AQueryable, Ownable2Step {
    error BaseURIFrozen();
    error InvalidAddress();
    error Unauthorized();
    error CannotResetManager();
    error Nonexistent();

    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event ManagerSet(address indexed _manager);

    address public manager;

    string private _base;
    bool public baseURIFrozen;
    uint256 public metadataVersion;
    uint256 public totalMinted;

    constructor() ERC721A("The Moonpot NFT", "TMPNFT") Ownable(msg.sender) {}

    modifier onlyManager() {
        if (msg.sender != manager) revert Unauthorized();
        _;
    }

    function mintTo(
        address to,
        uint256 quantity,
        uint256 roundId
    ) external onlyManager {
        uint256 startTokenId = _nextTokenId();

        _safeMint(to, quantity);
        _setExtraDataAt(startTokenId, uint24(roundId));

        unchecked {
            totalMinted = totalMinted + quantity;
        }
    }

    function getRound(uint256 tokenId) public view returns (uint256) {
        return uint256(_ownershipOf(tokenId).extraData);
    }

    function setManager(address _manager) external onlyOwner {
        if (_manager == address(0)) revert InvalidAddress();
        if (manager != address(0)) revert CannotResetManager();

        manager = _manager;
        emit ManagerSet(_manager);
    }

    function setBaseURI(string calldata newBase) external onlyOwner {
        if (baseURIFrozen) revert BaseURIFrozen();

        _base = newBase;

        unchecked {
            metadataVersion += 1;
        }

        if (totalMinted > 0) emit BatchMetadataUpdate(0, totalMinted - 1);
    }

    function freezeBaseURI() external onlyOwner {
        baseURIFrozen = true;
    }

    function _baseURI() internal view override returns (string memory) {
        return _base;
    }
}
