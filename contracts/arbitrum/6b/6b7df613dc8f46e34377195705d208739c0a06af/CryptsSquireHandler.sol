//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CryptsSquireHandlerContracts.sol";

contract CryptsSquireHandler is
    Initializable,
    CryptsSquireHandlerContracts
{

    function initialize() external initializer {
        CryptsSquireHandlerContracts.__CryptsSquireHandlerContracts_init();

        _setSquireDiversionPoints(5); // Same as aux common legions
        _setSquirePercentOfPoolClaimed(200); // 0.2% same as aux common legions
    }

    function setStakingAllowed(bool _stakingAllowed) external onlyAdminOrOwner {
        _setStakingAllowed(_stakingAllowed);
    }

    function _setStakingAllowed(bool _stakingAllowed) private {
        stakingAllowed = _stakingAllowed;
    }

    function _setSquireDiversionPoints(uint24 _squireDiversionPoints) private {
        squireDiversionPoints = _squireDiversionPoints;
        emit SquireDiversionPointsChanged(_squireDiversionPoints);
    }

    function _setSquirePercentOfPoolClaimed(uint32 _squirePercentOfPoolClaimed) private {
        squirePercentOfPoolClaimed = _squirePercentOfPoolClaimed;
        emit SquirePercentOfPoolClaimedChanged(_squirePercentOfPoolClaimed);
    }

    function handleStake(CharacterInfo memory _characterInfo, address _user)
        public
    {
        require(msg.sender == address(corruptionCrypts), "Must call from crypts");
        require(stakingAllowed, "Staking is not enabled");

        //Transfer it to the staking contract
        IERC721(squireAddress).safeTransferFrom(
            _user,
            address(this),
            _characterInfo.tokenId
        );
    }

    function handleUnstake(CharacterInfo memory _characterInfo, address _user)
        public
    {
        require(msg.sender == address(corruptionCrypts), "Must call from crypts");

        //Transfer it from the staking contract
        IERC721(squireAddress).safeTransferFrom(
            address(this),
            _user,
            _characterInfo.tokenId
        );
    }

    function getCorruptionDiversionPointsForToken(uint32) public view returns(uint24) {
        return squireDiversionPoints;
    }

    function getCorruptionCraftingClaimedPercent(uint32) public view returns(uint32){
        return squirePercentOfPoolClaimed;
    }
}

