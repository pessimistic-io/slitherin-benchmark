//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./MerkleProofUpgradeable.sol";

import "./AdvancedQuestingFixContracts.sol";

contract AdvancedQuestingFix is Initializable, AdvancedQuestingFixContracts {

    function initialize() external initializer {
        AdvancedQuestingFixContracts.__AdvancedQuestingFixContracts_init();
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdminOrOwner {
        merkleRoot = _merkleRoot;
    }

    function haveLegionsBeenFixed(uint256[] calldata _legionIds) external view returns(bool[] memory) {
        bool[] memory _haveBeenFixed = new bool[](_legionIds.length);

        for(uint256 i = 0; i < _legionIds.length; i++) {
            _haveBeenFixed[i] = legionIdToHasUncorruptedLegion[_legionIds[i]];
        }

        return _haveBeenFixed;
    }

    function fixLegions(
        FixLegionParams[] calldata _fixLegionParams)
    external
    whenNotPaused
    onlyEOA
    {
        require(_fixLegionParams.length > 0, "0 Length");
        EmergencyEndQuestingParams[] memory _endParams = new EmergencyEndQuestingParams[](_fixLegionParams.length);

        for(uint256 i = 0; i < _fixLegionParams.length; i++) {
            FixLegionParams calldata _params = _fixLegionParams[i];

            require(
                !legionIdToHasUncorruptedLegion[_params.legionId],
                "Already uncorrupted legion"
            );

            bytes32 _leaf = keccak256(abi.encodePacked(_params.legionId, msg.sender, _params.treasureIds, _params.treasureAmounts, _params.zone));

            require(
                MerkleProofUpgradeable.verify(_params.proof, merkleRoot, _leaf),
                "Proof invalid"
            );

            legionIdToHasUncorruptedLegion[_params.legionId] = true;

            _endParams[i] = EmergencyEndQuestingParams(
                _params.legionId,
                msg.sender,
                _params.zone,
                _params.treasureIds,
                _params.treasureAmounts
            );
        }

        advancedQuesting.emergencyEndQuesting(_endParams);
    }

    function fixLegionsAdmin(
        FixLegionParams[] calldata _fixLegionParams,
        address[] calldata _owners)
    external
    whenNotPaused
    onlyAdminOrOwner
    onlyEOA
    {
        require(_fixLegionParams.length > 0, "0 Length");
        EmergencyEndQuestingParams[] memory _endParams = new EmergencyEndQuestingParams[](_fixLegionParams.length);

        for(uint256 i = 0; i < _fixLegionParams.length; i++) {
            FixLegionParams calldata _params = _fixLegionParams[i];
            address _owner = _owners[i];

            require(
                !legionIdToHasUncorruptedLegion[_params.legionId],
                "Already uncorrupted legion"
            );

            bytes32 _leaf = keccak256(abi.encodePacked(_params.legionId, _owner, _params.treasureIds, _params.treasureAmounts, _params.zone));

            require(
                MerkleProofUpgradeable.verify(_params.proof, merkleRoot, _leaf),
                "Proof invalid"
            );

            legionIdToHasUncorruptedLegion[_params.legionId] = true;

            _endParams[i] = EmergencyEndQuestingParams(
                _params.legionId,
                _owner,
                _params.zone,
                _params.treasureIds,
                _params.treasureAmounts
            );
        }

        advancedQuesting.emergencyEndQuesting(_endParams);
    }

}

struct FixLegionParams {
    uint256 legionId;
    string zone;
    uint256[] treasureIds;
    uint256[] treasureAmounts;
    bytes32[] proof;
}
