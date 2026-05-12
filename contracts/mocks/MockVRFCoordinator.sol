// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

interface IVRFConsumerV2Plus {
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external;
}

contract DeployableVRFCoordinatorV2_5Mock {
    struct StoredReq {
        address consumer;
        uint32 callbackGasLimit;
        uint32 numWords;
    }

    uint256 private _nextRequestId = 1;
    mapping(uint256 => StoredReq) public requests; // requestId => request

    event RandomWordsRequested(
        uint256 indexed requestId,
        address indexed consumer,
        uint32 numWords,
        uint32 callbackGasLimit
    );
    event RandomWordsFulfilled(
        uint256 indexed requestId,
        address indexed consumer,
        bool success
    );

    // ─────────────────────────────────────────────────────────────────────────────
    // Phase 1: accept request (no subscriptions/extraArgs validation for local)
    // ─────────────────────────────────────────────────────────────────────────────
    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest calldata _req
    ) external returns (uint256 requestId) {
        requestId = _nextRequestId++;
        requests[requestId] = StoredReq({
            consumer: msg.sender,
            callbackGasLimit: _req.callbackGasLimit,
            numWords: _req.numWords
        });

        emit RandomWordsRequested(
            requestId,
            msg.sender,
            _req.numWords,
            _req.callbackGasLimit
        );
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Phase 2: fulfill later in a separate tx (no reentrancy issues)
    // ─────────────────────────────────────────────────────────────────────────────
    function fulfill(uint256 requestId) external {
        StoredReq memory r = requests[requestId];
        require(r.consumer != address(0), "invalid requestId");

        // Derive deterministic words for tests
        uint256[] memory words = new uint256[](r.numWords);
        for (uint256 i = 0; i < r.numWords; i++) {
            words[i] = uint256(keccak256(abi.encode(requestId, r.consumer, i)));
        }

        try
            IVRFConsumerV2Plus(r.consumer).rawFulfillRandomWords(
                requestId,
                words
            )
        {
            emit RandomWordsFulfilled(requestId, r.consumer, true);
            delete requests[requestId]; // prevent double-fulfillment
        } catch {
            emit RandomWordsFulfilled(requestId, r.consumer, false);
        }
    }

    // Convenience helpers (optional)
    function latestRequestId() external view returns (uint256) {
        return _nextRequestId == 0 ? 0 : _nextRequestId - 1;
    }

    function getRequest(
        uint256 requestId
    )
        external
        view
        returns (address consumer, uint32 callbackGasLimit, uint32 numWords)
    {
        StoredReq memory r = requests[requestId];
        return (r.consumer, r.callbackGasLimit, r.numWords);
    }
}
