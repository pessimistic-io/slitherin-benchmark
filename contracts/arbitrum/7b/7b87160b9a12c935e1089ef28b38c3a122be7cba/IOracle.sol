// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./SignatureLib.sol";

// Oracle
interface IOracle {
    struct Scratched {
        bytes16 scratchedPropositionId;
        // Timestamp of when the result was scratched
        uint256 timestamp;
        // Odds of the scratched proposition at time of scratching
        uint256 odds;
        // Total odds of all runners at time of scratching
        uint256 totalOdds;
    }

    struct Result {
        bytes16 winningPropositionId;
        Scratched [] scratched;
	}

    function checkResult(
        bytes16 marketId,
        bytes16 propositionId
    ) external view returns (uint8);

    function getResult(bytes16 marketId) external view returns (Result memory);

    function setResult(
        bytes16 marketId,
        bytes16 propositionId,
        SignatureLib.Signature calldata signature
    ) external;

	function setScratchedResult(
		bytes16 marketId,
		bytes16 scratchedPropositionId,
        uint256 odds,
        uint256 totalOdds,
		SignatureLib.Signature calldata signature
	) external;

    event ResultSet(bytes16 indexed marketId, bytes16 indexed propositionId);
    event ScratchedSet(bytes16 indexed marketId, bytes16 indexed propositionId);
}
