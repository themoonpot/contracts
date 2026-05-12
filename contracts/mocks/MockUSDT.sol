// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MockUSDT is ERC20 {
    using ECDSA for bytes32;

    // Explicitly storage for the separator
    bytes32 public DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    // Standard Permit TypeHash
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    constructor() ERC20("USDT0", "MUSDT") {
        _mint(msg.sender, 5_000_000_000e6);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,address verifyingContract,bytes32 salt)"
                ),
                keccak256(bytes("USDT0")),
                keccak256(bytes("1")),
                address(this),
                bytes32(block.chainid)
            )
        );
    }

    function decimals() public pure override returns (uint8) {
        return 6;
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
        require(deadline == 0 || block.timestamp <= deadline, "MUSDT: EXPIRED");

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address signer = ecrecover(digest, v, r, s);
        require(
            signer != address(0) && signer == owner,
            "MUSDT: INVALID_SIGNER"
        );

        _approve(owner, spender, value);
    }
}
