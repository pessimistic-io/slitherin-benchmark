pragma solidity ^0.8.4;
// SPDX-License-Identifier: BUSL-1.1

import "./LBFR.sol";
import "./Ownable.sol";
import "./ECDSA.sol";

contract FaucetLBFR is Ownable {
    LBFR public token;

    address public verifiedSigner;
    uint256 public timeOffset = 0;

    event Claim(address account, uint256 claimedTokens, uint256 weekID);
    mapping(address => mapping(uint256 => uint256))
        public totalTokensAllocatedPerUserPerWeek;

    constructor(LBFR _token, address _verifiedSigner) {
        token = _token;
        verifiedSigner = _verifiedSigner;
    }

    function setTimeOffset(uint256 value) external onlyOwner {
        timeOffset = value;
    }

    function getWeekID() public view returns (uint256 weekID) {
        weekID = (block.timestamp - timeOffset) / (86400 * 7);
    }

    function _validateSigner(
        uint256 weekID,
        uint256 currentWeekTokenAllocation,
        uint256 formerWeekTokenAllocation,
        address sender,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 digest = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    currentWeekTokenAllocation,
                    formerWeekTokenAllocation,
                    weekID,
                    sender
                )
            )
        );
        (address recoveredSigner, ECDSA.RecoverError error) = ECDSA.tryRecover(
            digest,
            signature
        );
        if (error == ECDSA.RecoverError.NoError) {
            return recoveredSigner == verifiedSigner;
        } else {
            return false;
        }
    }

    function _claim(uint256 tokensAllocated, uint256 weekID) internal {
        if (
            (tokensAllocated == 0) ||
            (tokensAllocated <=
                totalTokensAllocatedPerUserPerWeek[msg.sender][weekID])
        ) {
            return;
        }
        uint256 claimableTokens = tokensAllocated -
            totalTokensAllocatedPerUserPerWeek[msg.sender][weekID];

        token.mint(msg.sender, claimableTokens);
        totalTokensAllocatedPerUserPerWeek[msg.sender][
            weekID
        ] = tokensAllocated;

        emit Claim(msg.sender, claimableTokens, weekID);
    }

    function claim(
        bytes memory signature,
        uint256 currentWeekTokenAllocation,
        uint256 formerWeekTokenAllocation,
        uint256 weekID
    ) external {
        require(
            weekID == getWeekID(),
            "Claiming only allowed for current week"
        );
        require(
            _validateSigner(
                weekID,
                currentWeekTokenAllocation,
                formerWeekTokenAllocation,
                msg.sender,
                signature
            ),
            "Invalid signature"
        );

        _claim(currentWeekTokenAllocation, weekID);
        _claim(formerWeekTokenAllocation, weekID - 1);
    }
}

