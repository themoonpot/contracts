// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MockUSDC is ERC20 {
    using ECDSA for bytes32;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // The constant from the Circle EIP712 library you found
    bytes32 public constant DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    mapping(address => uint256) private _permitNonces;

    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 10_000_000_000 * 10 ** 6);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function nonces(address owner) external view returns (uint256) {
        return _permitNonces[owner];
    }

    /**
     * @notice Matches Circle's EIP712.makeDomainSeparator logic
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes("USD Coin")),
                    keccak256(bytes("2")),
                    block.chainid,
                    address(this)
                )
            );
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "MockUSDC: permit expired");

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                _permitNonces[owner]++,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash)
        );

        address signer = digest.recover(v, r, s);
        require(
            signer != address(0) && signer == owner,
            "MockUSDC: invalid signature"
        );

        _approve(owner, spender, value);
    }
}
