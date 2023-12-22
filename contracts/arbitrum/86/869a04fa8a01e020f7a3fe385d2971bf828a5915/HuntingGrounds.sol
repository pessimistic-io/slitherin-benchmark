//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./HuntingGroundsSettings.sol";

contract HuntingGrounds is Initializable, HuntingGroundsSettings {

    function initialize() external initializer {
        HuntingGroundsSettings.__HuntingGroundsSettings_init();
    }

    function startHunting(
        uint256 _tokenId)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    contractsAreSet
    {
        tokenIdToLastClaimedTime[_tokenId] = block.timestamp;

        emit StartedHunting(_tokenId, block.timestamp);
    }

    function stopHunting(
        uint256 _tokenId,
        address _owner)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    contractsAreSet
    {
        _claimBugz(_tokenId, _owner);

        delete tokenIdToLastClaimedTime[_tokenId];

        emit StoppedHunting(_tokenId);
    }

    function claimBugz(
        uint256[] calldata _tokenIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_tokenIds)
    {

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(world.ownerForStakedToad(_tokenIds[i]) == msg.sender, "HuntingGrounds: User does not own Toad");
            require(world.locationForStakedToad(_tokenIds[i]) == Location.HUNTING_GROUNDS, "HuntingGrounds: Toad is not at hunting grounds");

            _claimBugz(_tokenIds[i], msg.sender);
        }
    }

    function _claimBugz(uint256 _tokenId, address _to) private {
        uint256 _lastClaimTime = tokenIdToLastClaimedTime[_tokenId];
        require(_lastClaimTime > 0, "HuntingGrounds: Cannot have a last claim time of 0");

        uint256 _bugzAmount = (block.timestamp - tokenIdToLastClaimedTime[_tokenId]) * bugzAmountPerDay / 1 days;
        require(_bugzAmount > 0, "HuntingGrounds: Cannot claim 0 bugz");

        tokenIdToLastClaimedTime[_tokenId] = block.timestamp;

        ownerToTokenIdToTotalBugzClaimed[_to][_tokenId] += _bugzAmount;

        _mintBadgezIfNeeded(_to, _tokenId);

        bugz.mint(_to, _bugzAmount);

        emit ClaimedBugz(_tokenId, _bugzAmount, block.timestamp);
    }

    function _mintBadgezIfNeeded(address _to, uint256 _tokenId) private {
        for(uint256 i = 0; i < bugzBadgezAmounts.length; i++) {
            uint256 _bugzBadgeAmount = bugzBadgezAmounts[i];

            if(ownerToTokenIdToTotalBugzClaimed[_to][_tokenId] >= _bugzBadgeAmount) {
                require(bugzAmountToBadgeId[_bugzBadgeAmount] > 0, "HuntingGrounds: Badge id not set");

                badgez.mintIfNeeded(_to, bugzAmountToBadgeId[_bugzBadgeAmount]);
            }
        }
    }
}
