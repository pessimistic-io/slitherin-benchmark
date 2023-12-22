// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IPABStake.sol";
import "./PABStakeBase.sol";
import "./IPeekABoo.sol";
import "./IBOO.sol";
import "./IStakeManager.sol";

contract PABStake is
    Initializable,
    IPABStake,
    OwnableUpgradeable,
    PausableUpgradeable,
    PABStakeBase
{
    function initialize(
        address _peekaboo,
        address _BOO,
        uint256[6] memory _daily_boo_reward_rate
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        peekaboo = IPeekABoo(_peekaboo);
        boo = IBOO(_BOO);
        DAILY_BOO_RATE = [
            10 ether,
            15 ether,
            20 ether,
            25 ether,
            30 ether,
            35 ether
        ];
        EMISSION_RATE = 2;
        MINIMUM_TO_EXIT = 1 days;
    }

    /** STAKING */

    function normalStakePeekABoos(uint16[] calldata tokenIds) external {
        require(tx.origin == _msgSender(), "No SmartContracts");
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                peekabooRef.ownerOf(tokenIds[i]) == _msgSender(),
                "Not your token"
            );
            smRef.stakePABOnService(tokenIds[i], address(this), _msgSender());
            addPeekABoo(_msgSender(), tokenIds[i]);
        }
    }

    function addPeekABoo(address account, uint256 tokenId)
        internal
        whenNotPaused
    {
        pabstake[tokenId] = PeekABooNormalStaked({
            tokenId: tokenId,
            value: block.timestamp,
            owner: account
        });
        totalPeekABooStaked += 1;
        emit TokenStaked(account, tokenId, block.timestamp);
    }

    /** CLAIMING / UNSTAKING */

    function claimMany(uint16[] calldata tokenIds) external whenNotPaused {
        uint256 tobePaid = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tobePaid += claimPeekABoo(tokenIds[i], false);
        }
        if (tobePaid == 0) return;
        totalBooEarned += tobePaid;
        boo.mint(_msgSender(), tobePaid);
    }

    function unstakeMany(uint16[] calldata tokenIds) external whenNotPaused {
        uint256 tobePaid = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tobePaid += claimPeekABoo(tokenIds[i], true);
        }
        if (tobePaid == 0) return;
        totalBooEarned += tobePaid;
        boo.mint(_msgSender(), tobePaid);
    }

    function claimPeekABoo(uint256 tokenId, bool unstake)
        internal
        virtual
        returns (uint256 toBePaid)
    {
        PeekABooNormalStaked memory peekabooStaked = pabstake[tokenId];
        IPeekABoo peekabooRef = peekaboo;
        IStakeManager smRef = sm;

        require(smRef.ownerOf(tokenId) == _msgSender(), "Not Staked");
        require(
            peekabooStaked.value > 0 &&
                block.timestamp - peekabooStaked.value >= MINIMUM_TO_EXIT,
            "Must have atleast 1 day worth of $IBOO"
        );
        uint256 emission = 100 -
            ((EMISSION_RATE * peekabooRef.getPhase2Minted()) / 1000);
        if (totalBooEarned < boo.cap()) {
            toBePaid =
                (((block.timestamp - peekabooStaked.value) *
                    DAILY_BOO_RATE[peekabooRef.getTokenTraits(tokenId).tier] *
                    emission) / 100) /
                1 days;
        } else if (peekabooStaked.value > lastClaimTimestamp) {
            toBePaid = 0; // $IBOO production stopped already
        } else {
            toBePaid =
                (((lastClaimTimestamp - peekabooStaked.value) *
                    DAILY_BOO_RATE[peekabooRef.getTokenTraits(tokenId).tier] *
                    emission) / 100) /
                1 days; // stop earning additional $IBOO if it's all been earned
        }

        if (unstake) {
            smRef.unstakePeekABoo(tokenId);
            delete pabstake[tokenId];
        } else {
            pabstake[tokenId] = PeekABooNormalStaked({
                owner: _msgSender(),
                tokenId: tokenId,
                value: block.timestamp
            }); // reset pabstake
        }
        emit PeekABooClaimed(tokenId, toBePaid, unstake);
    }

    /** ACCOUNTING */
    /**
     * enables owner to pause / unpause minting
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function setDailyBOORate(uint256[6] memory _daily_boo_reward_rate)
        external
        onlyOwner
    {
        DAILY_BOO_RATE = _daily_boo_reward_rate;
    }

    function setBOO(address _boo) public onlyOwner {
        boo = IBOO(_boo);
    }

    function setPeekABoo(address _peekaboo) public onlyOwner {
        peekaboo = IPeekABoo(_peekaboo);
    }

    function setStakeManager(address _sm) public onlyOwner {
        sm = IStakeManager(_sm);
    }

    function canClaimGhost(uint256 tokenId) external view returns (bool) {
        require(peekaboo.getTokenTraits(tokenId).isGhost, "Not a ghost");
        return block.timestamp - pabstake[tokenId].value >= 1 days;
    }

    function getTimestamp(uint256[] calldata tokenIds)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory timestamps = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            timestamps[i] = (pabstake[tokenIds[i]].value);
        }
        return timestamps;
    }

    function getPeekABooValue(uint256[] calldata tokenIds)
        external
        view
        virtual
        returns (uint256[] memory)
    {
        IPeekABoo peekabooRef = peekaboo;
        uint256[] memory timestamps = getTimestamp(tokenIds);
        uint256[] memory values = new uint256[](tokenIds.length);
        uint256 toBePaid;
        uint256 emission = 100 -
            ((EMISSION_RATE * peekabooRef.getPhase2Minted()) / 1000);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(timestamps[i] > 0, "Not staked");
            if (totalBooEarned < boo.cap()) {
                toBePaid =
                    (((block.timestamp - timestamps[i]) *
                        DAILY_BOO_RATE[
                            peekabooRef.getTokenTraits(tokenIds[i]).tier
                        ] *
                        emission) / 100) /
                    1 days;
            } else if (timestamps[i] > lastClaimTimestamp) {
                toBePaid = 0; // $IBOO production stopped already
            } else {
                toBePaid =
                    (((lastClaimTimestamp - timestamps[i]) *
                        DAILY_BOO_RATE[
                            peekabooRef.getTokenTraits(tokenIds[i]).tier
                        ] *
                        emission) / 100) /
                    1 days; // stop earning additional $IBOO if it's all been earned
            }
            values[i] = toBePaid;
        }
        return values;
    }

    function setDailyBooRate(uint256[6] memory _dailyBooRate)
        external
        onlyOwner
    {
        DAILY_BOO_RATE = _dailyBooRate;
    }

    function setEmissionRate(uint256 _emission) external onlyOwner {
        EMISSION_RATE = _emission;
    }
}

