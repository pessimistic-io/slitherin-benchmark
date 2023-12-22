//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CryptsBeaconHandlerContracts.sol";

contract CryptsBeaconHandler is
    Initializable,
    CryptsBeaconHandlerContracts
{

    function initialize() external initializer {
        CryptsBeaconHandlerContracts.__CryptsBeaconHandlerContracts_init();

        //                               ||
        //                               ||
        //  TODO Make sure this correct  ||
        //                               ||
        //                              \  /
        //                               \/
        _setBeaconDiversionPoints(30); // Same as aux uncommon legions
        _setBeaconPercentOfPoolClaimed(210); // 0.21%
    }

    function setStakingAllowed(bool _stakingAllowed) external onlyAdminOrOwner {
        _setStakingAllowed(_stakingAllowed);
    }

    function _setStakingAllowed(bool _stakingAllowed) private {
        stakingAllowed = _stakingAllowed;
    }

    function _setBeaconDiversionPoints(uint24 _beaconDiversionPoints) private {
        beaconDiversionPoints = _beaconDiversionPoints;
        emit BeaconDiversionPointsChanged(_beaconDiversionPoints);
    }

    function _setBeaconPercentOfPoolClaimed(uint32 _beaconPercentOfPoolClaimed) private {
        beaconPercentOfPoolClaimed = _beaconPercentOfPoolClaimed;
        emit BeaconPercentOfPoolClaimedChanged(_beaconPercentOfPoolClaimed);
    }

    function handleStake(CharacterInfo memory _characterInfo, address _user)
        public
    {
        require(msg.sender == address(corruptionCrypts), "Must call from crypts");
        require(stakingAllowed, "Staking is not enabled");
        require(_characterInfo.tokenId < 4097, "Not a valid pet ID");

        //Transfer it to the staking contract
        IERC1155(beaconAddress).safeTransferFrom(
            _user,
            address(this),
            _characterInfo.tokenId,
            1,
            ""
        );
    }

    function handleUnstake(CharacterInfo memory _characterInfo, address _user)
        public
    {
        require(msg.sender == address(corruptionCrypts), "Must call from crypts");
        require(_characterInfo.tokenId < 4097, "Not a valid pet ID");

        //Transfer it from the staking contract
        IERC1155(beaconAddress).safeTransferFrom(
            address(this),
            _user,
            _characterInfo.tokenId,
            1,
            ""
        );
    }

    function getCorruptionDiversionPointsForToken(uint32) public view returns(uint24) {
        return beaconDiversionPoints;
    }

    function getCorruptionCraftingClaimedPercent(uint32) public view returns(uint32){
        return beaconPercentOfPoolClaimed;
    }
}

