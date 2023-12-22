// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./SignatureLib.sol";

// Oracle
interface IOracle {
    struct Scratched {
        bytes16 propositionId;
        // Timestamp of when the result was scratched
        uint256 timestamp;
        // Odds of the scratched proposition at time of scratching
        uint256 odds;
    }

    struct Result {
        bytes16 winningPropositionId;
        Scratched[] scratched;
	}

    function hasResult(bytes16 marketId) external view returns (bool);

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
		bytes16 propositionId,
        uint256 odds,
		SignatureLib.Signature calldata signature
	) external;

    event ResultSet(bytes16 indexed marketId, bytes16 indexed propositionId);
    event ScratchedSet(bytes16 indexed marketId, bytes16 indexed propositionId);
}
