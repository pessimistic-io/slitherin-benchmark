//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Lib } from "./Lib.sol";
import { IPits } from "./IPits.sol";
import { IBones } from "./IBones.sol";
import { IRandomizer } from "./IRandomizer.sol";
import { INeandersmol } from "./INeandersmol.sol";
import { Ownable } from "./Ownable.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";

import {     Initializable } from "./Initializable.sol";
import {     Jobs,     Grounds,     BonesFeInfo,     LaborGround,     DevGroundFeInfo,     DevelopmentGround } from "./StructsEnums.sol";
import {     InvalidPos,     NotYourToken,     TokenIsStaked,     WrongMultiple,     LengthsNotEqual,     InvalidLockTime,     ZeroBalanceError,     CsIsBellowHundred,     NeandersmolsIsLocked,     BalanceIsInsufficient,     DevelopmentGroundIsLocked,     NeandersmolIsNotInDevelopmentGround } from "./Error.sol";

contract DevelopmentGrounds is Initializable, Ownable {
    IBones public bones;
    IPits public pits;
    INeandersmol public neandersmol;

    function initialize(
        address _pits,
        address _neandersmol,
        address _bones
    ) external initializer {
        _initializeOwner(msg.sender);
        setAddress(_pits, _neandersmol, _bones);
    }

    // tokenId -> amount position -> staking time
    mapping(uint256 => mapping(uint256 => uint256)) private trackTime;
    // tokenId -> time -> amount
    mapping(uint256 => mapping(uint256 => uint256)) private trackToken;

    mapping(address => uint256[]) private ownerToTokens;

    mapping(uint256 => DevelopmentGround) private developmentGround;

    uint256 private constant MINIMUM_BONE_STAKE = 1000 * 10 ** 18;

    function setAddress(
        address _pits,
        address _neandersmol,
        address _bones
    ) public onlyOwner {
        bones = IBones(_bones);
        pits = IPits(_pits);
        neandersmol = INeandersmol(_neandersmol);
    }

    /**
     * @dev Enters the DevelopmentGround by transferring the tokens from the sender to the contract
     * and setting the development ground data such as owner, entry time, lock period, etc.
     * @param _tokenId Array of token IDs to be transferred
     * @param _lockTime Array of lock times for each corresponding token
     * @param _ground Array of grounds for each corresponding token
     */

    function enterDevelopmentGround(
        uint256[] calldata _tokenId,
        uint256[] calldata _lockTime,
        Grounds[] calldata _ground
    ) external {
        uint256 i;
        checkLength(_tokenId, _lockTime);
        if (_lockTime.length != _ground.length) revert LengthsNotEqual();
        Lib.pitsValidation(pits);
        for (; i < _tokenId.length; ++i) {
            (uint256 tokenId, uint256 lockTime) = (_tokenId[i], _lockTime[i]);
            if (neandersmol.staked(tokenId)) revert TokenIsStaked();
            DevelopmentGround storage devGround = developmentGround[tokenId];
            if (neandersmol.getCommonSense(tokenId) < 100)
                revert CsIsBellowHundred();
            if (neandersmol.ownerOf(tokenId) != msg.sender)
                revert NotYourToken();

            if (!lockTimeExists(lockTime)) revert InvalidLockTime();
            neandersmol.stakingHandler(tokenId, true);
            devGround.owner = msg.sender;
            devGround.entryTime = uint64(block.timestamp);
            devGround.lockPeriod = uint64(lockTime);
            devGround.lastRewardTime = uint64(block.timestamp);
            devGround.ground = _ground[i];
            devGround.currentPitsLockPeriod = pits.getTimeOut();
            ownerToTokens[msg.sender].push(tokenId);
            emit EnterDevelopmentGround(
                msg.sender,
                tokenId,
                lockTime,
                block.timestamp,
                _ground[i]
            );
        }
    }

    /**
     * @dev Stakes the bones in the DevelopmentGround by transferring the bones from the sender to the contract
     * and updating the development ground data.
     * @param _amount Array of amounts of bones to be transferred
     * @param _tokenId Array of token IDs for the corresponding amounts of bones
     */

    function stakeBonesInDevelopmentGround(
        uint256[] calldata _amount,
        uint256[] calldata _tokenId
    ) external {
        Lib.pitsValidation(pits);
        checkLength(_amount, _tokenId);
        uint256 i;
        for (; i < _amount.length; ++i) {
            (uint256 tokenId, uint256 amount) = (_tokenId[i], _amount[i]);
            DevelopmentGround storage devGround = developmentGround[tokenId];
            if (bones.balanceOf(msg.sender) < amount)
                revert BalanceIsInsufficient();
            if (devGround.owner != msg.sender)
                revert NeandersmolIsNotInDevelopmentGround();
            if (amount % MINIMUM_BONE_STAKE != 0) revert WrongMultiple();
            SafeTransferLib.safeTransferFrom(
                address(bones),
                msg.sender,
                address(this),
                amount
            );
            updateDevelopmentGround(devGround, tokenId, amount);
            emit StakeBonesInDevelopmentGround(msg.sender, amount, tokenId);
        }
    }

    /**
     * @dev Removes bones from a specific development ground.
     * @param _tokenId The unique identifier for the development ground
     * @param _all Indicates whether to remove all bones or just a portion of them
     */

    function removeBones(
        uint256[] calldata _tokenId,
        bool[] calldata _all
    ) external {
        if (_tokenId.length != _all.length) revert LengthsNotEqual();
        uint256 i;
        for (; i < _tokenId.length; ++i) {
            if (getPrimarySkill(_tokenId[i]) > 0)
                developPrimarySkill(_tokenId[i]);
            removeBones(_tokenId[i], _all[i]);
        }
    }

    function calculateBones(
        address _owner
    ) external view returns (uint256, uint256) {
        uint256[] memory stakedTokens = ownerToTokens[_owner];
        uint256 thetaxed;
        uint256 theuntaxed;
        for (uint256 i; i < stakedTokens.length; ++i) {
            (uint256 t, uint256 u) = calculateBones(stakedTokens[i]);
            thetaxed += t;
            theuntaxed += u;
        }

        return (thetaxed, theuntaxed);
    }

    function calculateBones(
        uint256 _tokenId
    ) internal view returns (uint256, uint256) {
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        if (devGround.bonesStaked == 0) return (0, 0);
        uint256 i = 1;
        uint256 amountUnTaxed;
        uint256 amountTaxed;

        /**
         * return amount of bones to be taxed
         */

        for (; i <= devGround.amountPosition; ++i) {
            uint256 time = trackTime[_tokenId][i];

            block.timestamp < time + 30 days
                ? amountTaxed += trackToken[_tokenId][time]
                : amountUnTaxed += trackToken[_tokenId][time];
        }

        return (amountTaxed, amountUnTaxed);
    }

    /**
     * @dev Helper function to remove bones from a specific development ground
     * @param _tokenId The unique identifier for the development ground
     * @param _all Indicates whether to remove all bones if it will be taxed or not
     */
    function removeBones(uint256 _tokenId, bool _all) internal {
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        if (devGround.owner != msg.sender) revert NotYourToken();
        if (devGround.bonesStaked == 0) revert ZeroBalanceError();

        uint256 i = 1;
        uint256 amount;
        uint64 count;

        for (; i <= devGround.amountPosition; ++i) {
            (uint256 time, uint256 prev) = (
                trackTime[_tokenId][i],
                trackTime[_tokenId][i + 1]
            );
            if (block.timestamp < time + 30 days && !_all) continue;

            block.timestamp < time + 30 days && _all && rand() % 2 == 0
                ? amount += trackToken[_tokenId][time] / 2
                : amount += trackToken[_tokenId][time];

            _all || devGround.amountPosition == 1
                ? trackTime[_tokenId][i] = 0
                : trackTime[_tokenId][i] = prev;
            trackToken[_tokenId][time] = 0;

            ++count;
        }

        developmentGround[_tokenId].amountPosition -= count;
        developmentGround[_tokenId].bonesStaked -= amount;

        uint256 bal = devGround.bonesStaked - amount;

        if (bal != 0 && _all) bones.burn(address(this), bal);

        if (amount != 0)
            SafeTransferLib.safeTransfer(address(bones), msg.sender, amount);

        emit RemoveBones(msg.sender, _tokenId, amount);
    }

    /**
     * @dev Allows the owner of a DevelopmentGround to remove a single bone from a specific position in the track.
     * @param _tokenId The ID of the DevelopmentGround.
     * @param _pos The position of the bone to be removed.
     */

    function removeSingleBones(uint256 _tokenId, uint256 _pos) external {
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        if (devGround.owner != msg.sender) revert NotYourToken();
        if (devGround.amountPosition < _pos) revert InvalidPos();
        if (devGround.bonesStaked == 0) revert ZeroBalanceError();
        developPrimarySkill(_tokenId);
        uint256 amount;
        uint256 time = trackTime[_tokenId][_pos];
        uint256 initialAmount = trackToken[_tokenId][time];

        block.timestamp < time + 30 days && rand() % 2 == 0
            ? amount += trackToken[_tokenId][time] / 2
            : amount += trackToken[_tokenId][time];

        devGround.amountPosition == 1
            ? trackTime[_tokenId][_pos] = 0
            : trackTime[_tokenId][_pos] = trackTime[_tokenId][_pos + 1];
        trackToken[_tokenId][time] = 0;
        developmentGround[_tokenId].amountPosition -= 1;
        uint256 bal = initialAmount - amount;

        if (bal != 0) bones.burn(address(this), bal);

        if (amount != 0)
            SafeTransferLib.safeTransfer(address(bones), msg.sender, bal);
        emit RemoveBones(msg.sender, _tokenId, amount);
    }

    /**
     *  This function develops the primary skill of the `_tokenId` development ground.
     * @param _tokenId ID of the development ground
     */

    function developPrimarySkill(uint256 _tokenId) internal {
        // make sure bones staked is more than 30% the total supply
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        (uint256 amount, Grounds ground) = (
            getPrimarySkill(_tokenId),
            devGround.ground
        );
        if (ground == Grounds.Chambers) {
            neandersmol.developMystics(_tokenId, amount);
        } else if (ground == Grounds.Garden) {
            neandersmol.developFarmers(_tokenId, amount);
        } else {
            neandersmol.developFighter(_tokenId, amount);
        }
    }

    /**
     * This function retrieves the primary skill of the `_tokenId` development ground.
     * @param _tokenId ID of the development ground
     * @return The primary skill level
     */

    function getPrimarySkill(uint256 _tokenId) public view returns (uint256) {
        DevelopmentGround memory token = developmentGround[_tokenId];

        return
            Lib.calculatePrimarySkill(
                token.bonesStaked,
                token.amountPosition,
                token.currentPitsLockPeriod,
                _tokenId,
                pits,
                trackTime,
                trackToken
            );
    }

    /**
     * This function allows the owner of the development ground to claim the rewards earned by the development ground.
     * @param _tokenId ID of the development ground
     * @param _stake Whether to stake the reward bones in the development ground
     */

    function claimDevelopmentGroundBonesReward(
        uint256 _tokenId,
        bool _stake
    ) internal {
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        if (devGround.owner != msg.sender) revert NotYourToken();
        uint256 reward = getDevelopmentGroundBonesReward(_tokenId);
        if (reward == 0) revert ZeroBalanceError();
        developmentGround[_tokenId].lastRewardTime = uint64(block.timestamp);
        _stake
            ? stakeBonesInDevelopmentGround(_tokenId, reward)
            : bones.mint(msg.sender, reward);

        emit ClaimDevelopmentGroundBonesReward(msg.sender, _tokenId, _stake);
    }

    /**
     * This function allows the owner of multiple development grounds to claim rewards earned by them.
     * @param _tokenId ID of the development ground
     * @param _stake Whether to stake the reward bones in the development ground
     */

    function claimDevelopmentGroundBonesReward(
        uint256[] calldata _tokenId,
        bool[] calldata _stake
    ) external {
        if (_tokenId.length != _stake.length) revert LengthsNotEqual();
        for (uint256 i; i < _tokenId.length; ++i)
            claimDevelopmentGroundBonesReward(_tokenId[i], _stake[i]);
    }

    /**
     * @dev Stakes the specified amount of Bones in the Development Ground of the specified token ID.
     * @param _tokenId The ID of the Neandersmol token that represents the Development Ground.
     * @param _amount The amount of Bones to be staked.
     */
    function stakeBonesInDevelopmentGround(
        uint256 _tokenId,
        uint256 _amount
    ) internal {
        uint256 remainder = _amount % MINIMUM_BONE_STAKE;
        if (remainder == _amount) revert WrongMultiple(); // if the amount is less than Minimum
        if (remainder != 0) bones.mint(msg.sender, remainder); // if the amount is greater than minimum but wrong multiple
        uint256 newAmount = _amount - remainder;
        updateDevelopmentGround(
            developmentGround[_tokenId],
            _tokenId,
            newAmount
        );
        bones.mint(address(this), newAmount);
        emit StakeBonesInDevelopmentGround(msg.sender, newAmount, _tokenId);
    }

    /**
     * @dev Returns the reward for the bones staked in the development ground.
     * @param _tokenId The token ID for the development ground.
     * @return The reward for the bones staked in the development ground.
     */

    function getDevelopmentGroundBonesReward(
        uint256 _tokenId
    ) public view returns (uint256) {
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        return
            Lib.getDevelopmentGroundBonesReward(
                devGround.currentPitsLockPeriod,
                devGround.lockPeriod,
                devGround.lastRewardTime,
                pits
            );
    }

    /**
     * @dev Allows the owner to leave the development ground. This will transfer the token back to the owner and remove any bones staked in the development ground.
     * @param _tokenId The token ID of the development ground to leave.
     */

    function leaveDevelopmentGround(uint256[] calldata _tokenId) external {
        for (uint256 i; i < _tokenId.length; ++i)
            leaveDevelopmentGround(_tokenId[i]);
    }

    /**
     * @dev Internal function for the leaveDevelopmentGround function to remove the development ground and transfer the token back to the owner.
     * @param _tokenId The token ID of the development ground to leave.
     */

    function leaveDevelopmentGround(uint256 _tokenId) internal {
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        if (devGround.owner != msg.sender) revert NotYourToken();
        if (block.timestamp < devGround.entryTime + devGround.lockPeriod)
            revert NeandersmolsIsLocked();
        if (getDevelopmentGroundBonesReward(_tokenId) > 0)
            claimDevelopmentGroundBonesReward(_tokenId, false);
        if (devGround.bonesStaked > 0) removeBones(_tokenId, true);
        Lib.removeItem(ownerToTokens[msg.sender], (_tokenId));
        delete developmentGround[_tokenId];
        neandersmol.stakingHandler(_tokenId, false);
        emit LeaveDevelopmentGround(msg.sender, _tokenId);
    }

    /**
     * @dev This function updates the DevelopmentGround by adding `_amount` to `_devGround.bonesStaked` and increments `_devGround.amountPosition`.
     * @param _devGround The DevelopmentGround to be updated.
     * @param _tokenId The token ID associated with the DevelopmentGround.
     * @param _amount The amount to be added to `_devGround.bonesStaked`.
     */

    function updateDevelopmentGround(
        DevelopmentGround storage _devGround,
        uint256 _tokenId,
        uint256 _amount
    ) internal {
        _devGround.bonesStaked += _amount;
        ++_devGround.amountPosition;
        trackToken[_tokenId][block.timestamp] = _amount;
        trackTime[_tokenId][_devGround.amountPosition] = block.timestamp;
    }

    /**
     *Check the length of two input arrays, _tokenId and _animalsId, for equality.
     *If the lengths are not equal, the function will revert with the error "LengthsNotEqual".
     *@dev Internal function called by other functions within the contract.
     *@param _tokenId Array of token IDs
     */

    function checkLength(
        uint256[] calldata _tokenId,
        uint256[] calldata _animalsId
    ) internal pure {
        if (_tokenId.length != _animalsId.length) revert LengthsNotEqual();
    }

    function rand() private view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp +
                        ((
                            uint256(keccak256(abi.encodePacked(block.coinbase)))
                        ) / (block.timestamp)) +
                        block.gaslimit +
                        ((uint256(keccak256(abi.encodePacked(msg.sender)))) /
                            (block.timestamp)) +
                        block.number
                )
            )
        );

        return seed;
    }

    function lockTimeExists(uint256 _lockTime) internal pure returns (bool) {
        return
            _lockTime == 50 days ||
            _lockTime == 100 days ||
            _lockTime == 150 days;
    }

    /*                                                                           */
    /*                           VIEW FUNCTIONS                                  */
    /*                                                                           */

    /**
     * Retrieve information about a Development Ground token.
     * @dev This function returns a DevelopmentGround struct containing information about a Development Ground token, specified by its ID, _tokenId.
     * @param _tokenId ID of the Development Ground token to retrieve information for
     * @return The DevelopmentGround struct containing information about the specified Development Ground token.
     */

    function getDevelopmentGroundInfo(
        uint256 _tokenId
    ) public view returns (DevelopmentGround memory) {
        return developmentGround[_tokenId];
    }

    /**
     * @dev Returns an array of token IDs that are currently staked by the given owner.
     * @param _owner The address of the owner.
     * @return An array of staked token IDs.
     */

    function getStakedTokens(
        address _owner
    ) external view returns (uint256[] memory) {
        return ownerToTokens[_owner];
    }

    /**
     * @dev Returns an array of BonesFeInfo structs containing information about the Bone tokens
     * staked at certain time.
     * @param _tokenId The ID of the token to retrieve information for.
     * @return An array of BonesFeInfo structs containing Bone token and timestamp information.
     */

    function bonesToTime(
        uint256 _tokenId
    ) external view returns (BonesFeInfo[] memory) {
        DevelopmentGround memory devGround = developmentGround[_tokenId];
        BonesFeInfo[] memory bonesFe = new BonesFeInfo[](
            devGround.amountPosition
        );
        uint256 i;
        for (; i < devGround.amountPosition; ++i) {
            uint256 time = trackTime[_tokenId][i + 1];
            uint256 amount = trackToken[_tokenId][time];
            bonesFe[i] = BonesFeInfo(amount, time);
        }

        return bonesFe;
    }

    /**
     * @dev Returns an array of DevGroundFeInfo structs containing information about the
     * DevelopmentGround tokens staked by the specified owner.
     * @param _owner The address of the owner.
     * @return An array of DevGroundFeInfo structs containing DevelopmentGround token information.
     */

    function getDevGroundFeInfo(
        address _owner
    ) external view returns (DevGroundFeInfo[] memory) {
        uint256[] memory stakedTokens = ownerToTokens[_owner];
        DevGroundFeInfo[] memory userInfo = new DevGroundFeInfo[](
            stakedTokens.length
        );

        uint256 i;
        for (; i < userInfo.length; ++i) {
            uint256 stakedToken = stakedTokens[i];
            DevelopmentGround memory devGround = getDevelopmentGroundInfo(
                stakedToken
            );
            uint256 unlockTime = devGround.lockPeriod + devGround.entryTime;
            uint256 timeLeft = block.timestamp < unlockTime
                ? (unlockTime - block.timestamp) / 1 days
                : 0;
            userInfo[i] = DevGroundFeInfo(
                uint96(timeLeft),
                uint96(block.timestamp - devGround.entryTime),
                uint64(stakedToken),
                getPrimarySkill(stakedToken),
                getDevelopmentGroundBonesReward(stakedToken),
                devGround.bonesStaked,
                devGround.ground
            );
        }

        return userInfo;
    }

    event EnterDevelopmentGround(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed lockTime,
        uint256 entryTime,
        Grounds ground
    );

    event ClaimDevelopmentGroundBonesReward(
        address indexed owner,
        uint256 indexed tokenId,
        bool indexed stake
    );

    event RemoveBones(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed amount
    );

    event LeaveDevelopmentGround(
        address indexed owner,
        uint256 indexed tokenId
    );

    event StakeBonesInDevelopmentGround(
        address indexed owner,
        uint256 indexed amount,
        uint256 indexed tokenId
    );
}

