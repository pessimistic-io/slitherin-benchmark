//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Lib } from "./Lib.sol";
import { IPits } from "./IPits.sol";
import { IRandomizer } from "./IRandomizer.sol";
import { INeandersmol } from "./INeandersmol.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { Ownable } from "./Ownable.sol";
import {     IConsumables,     IERC1155Upgradeable } from "./IConsumables.sol";
import {     Initializable } from "./Initializable.sol";

import {     LengthsNotEqual,     NotYourToken,     CannotClaimNow,     InvalidTokenForThisJob,     CsToHigh,     NoMoreAnimalsAllowed,     TokenIsStaked } from "./Error.sol";

import {     Jobs,     Grounds,     LaborGround,     LaborGroundFeInfo } from "./StructsEnums.sol";

import { ISupplies } from "./ISupplies.sol";

contract LaborGrounds is Initializable, Ownable {
    IPits public pits;
    IRandomizer private randomizer;
    IConsumables public consumables;
    INeandersmol public neandersmol;
    IERC1155Upgradeable public animals;
    IERC1155Upgradeable public supplies;

    uint32 constant MAX_UINT32 = type(uint32).max;

    mapping(uint256 => LaborGround) private laborGround;

    mapping(address => uint256[]) private ownerToTokens;

    function initialize(
        address _pits,
        address _animals,
        address _supplies,
        address _consumables,
        address _neandersmol,
        address _randomizer
    ) external initializer {
        _initializeOwner(msg.sender);
        setAddress(
            _pits,
            _animals,
            _supplies,
            _consumables,
            _neandersmol,
            _randomizer
        );
    }

    function setAddress(
        address _pits,
        address _animals,
        address _supplies,
        address _consumables,
        address _neandersmol,
        address _randomizer
    ) public onlyOwner {
        animals = IERC1155Upgradeable(_animals);
        pits = IPits(_pits);
        supplies = IERC1155Upgradeable(_supplies);
        randomizer = IRandomizer(_randomizer);
        consumables = IConsumables(_consumables);
        neandersmol = INeandersmol(_neandersmol);
    }

    /**
     * @notice Enters the labor ground with specified token ID and supply ID,
     * and assigns the job to it. Transfers the token and supply ownership to the contract.
     * Emits the "EnterLaborGround" event.
     * @param _tokenId Array of token IDs of the labor grounds.
     * @param _supplyId Array of supply IDs associated with the labor grounds.
     * @param _job Array of jobs assigned to the labor grounds.
     */

    function enterLaborGround(
        uint256[] calldata _tokenId,
        uint256[] calldata _supplyId,
        Jobs[] calldata _job
    ) external {
        Lib.pitsValidation(pits);
        checkLength(_tokenId, _supplyId);
        if (_supplyId.length != _job.length) revert LengthsNotEqual();
        uint256 i;
        for (; i < _tokenId.length; ++i) {
            (uint256 tokenId, uint256 supplyId) = (_tokenId[i], _supplyId[i]);
            if (neandersmol.staked(tokenId)) revert TokenIsStaked();
            if (neandersmol.ownerOf(tokenId) != msg.sender)
                revert NotYourToken();
            if (neandersmol.getCommonSense(tokenId) > 99) revert CsToHigh();
            if (!validateTokenId(supplyId, _job[i]))
                revert InvalidTokenForThisJob();
            supplies.safeTransferFrom(
                msg.sender,
                address(this),
                supplyId,
                1,
                ""
            );

            laborGround[tokenId] = LaborGround(
                msg.sender,
                uint32(block.timestamp),
                uint32(supplyId),
                MAX_UINT32,
                randomizer.requestRandomNumber(),
                _job[i]
            );
            neandersmol.stakingHandler(tokenId, true);
            ownerToTokens[msg.sender].push(tokenId);
            emit EnterLaborGround(msg.sender, tokenId, supplyId, _job[i]);
        }
    }

    /**
     *  Brings in animals to the labor ground by calling the bringInAnimalsToLaborGround function in the Lib library and transferring the ownership of the animal token from the sender to the contract.
     * @param _tokenId An array of token IDs representing the labor grounds.
     * @param _animalsId An array of token IDs representing the animals.
     */

    function bringInAnimalsToLaborGround(
        uint256[] calldata _tokenId,
        uint256[] calldata _animalsId
    ) external {
        checkLength(_tokenId, _animalsId);
        uint256 i;
        for (; i < _tokenId.length; ++i) {
            uint256 animalsId = _animalsId[i];
            LaborGround memory labor = laborGround[_tokenId[i]];
            if (labor.owner != msg.sender) revert NotYourToken();
            if (labor.animalId != MAX_UINT32) revert NoMoreAnimalsAllowed();
            animals.safeTransferFrom(
                msg.sender,
                address(this),
                animalsId,
                1,
                ""
            );
            laborGround[_tokenId[i]].animalId = uint32(animalsId);

            emit BringInAnimalsToLaborGround(
                msg.sender,
                _tokenId[i],
                animalsId
            );
        }
    }

    /**
     * @notice Removes the animals from the specified labor ground.
     * Transfers the ownership of the animals back to the sender.
     * @param _tokenId Array of token IDs of the labor grounds.

     */
    function removeAnimalsFromLaborGround(
        uint256[] calldata _tokenId
    ) external {
        uint256 i;
        for (; i < _tokenId.length; ++i) {
            LaborGround memory labor = laborGround[_tokenId[i]];
            uint256 animalsId = labor.animalId;
            if (labor.owner != msg.sender || animalsId == MAX_UINT32)
                revert NotYourToken();
            laborGround[_tokenId[i]].animalId = MAX_UINT32;
            animals.safeTransferFrom(
                address(this),
                msg.sender,
                animalsId,
                1,
                ""
            );

            emit RemoveAnimalsFromLaborGround(
                msg.sender,
                _tokenId[i],
                animalsId
            );
        }
    }

    /**
     * This function allows the token owner to claim a collectable. If the token owner is not the same as the
     * stored owner or the lock time has not yet passed, the function will revert. If there are possible claims,
     * a consumables token will be minted for the token owner. The lock time for the labor ground is then updated.
     * @param _tokenId The id of the labor ground token being claimed.
     */

    function claimCollectable(uint256 _tokenId) internal returns (bool) {
        LaborGround memory labor = laborGround[_tokenId];
        if (msg.sender != labor.owner) revert NotYourToken();
        if (block.timestamp < labor.lockTime + 3 days) revert CannotClaimNow();
        (uint256 consumablesTokenId, bool broken) = checkPossibleClaims(
            _tokenId,
            labor
        );
        if (consumablesTokenId != 0)
            consumables.mint(msg.sender, consumablesTokenId, 1);

        laborGround[_tokenId].lockTime = uint32(block.timestamp);
        emit ClaimCollectable(msg.sender, _tokenId);

        return broken;
    }

    /** 
    *@dev This function allows a user to claim multiple collectables at once by providing an array of token IDs.
     @param _tokenId An array of token IDs that the user wants to claim.
*/
    function claimCollectables(uint256[] calldata _tokenId) external {
        for (uint256 i; i < _tokenId.length; ++i) claimCollectable(_tokenId[i]);
    }

    /**
     * @dev This function decides whether the supply will break or fail when the random number generated is smaller than `_min`.
     * @param _tokenId ID of the token that the supply is associated with.
     * @param _supplyId ID of the supply.
     */

    function breakOrFailed(
        uint256 _tokenId,
        uint256 _supplyId,
        uint256 _random
    ) internal returns (bool) {
        if (_random == 0) {
            laborGround[_tokenId].supplyId = 0;
            ISupplies(address(supplies)).burn(msg.sender, _supplyId, 1);
            leaveLg(_tokenId);
            return true;
        } else {
            return false;
        }
    }

    function leaveLg(uint256 _tokenId) internal {
        LaborGround memory labor = laborGround[_tokenId];
        if (labor.owner != msg.sender) revert NotYourToken();
        delete laborGround[_tokenId];
        Lib.removeItem(ownerToTokens[msg.sender], _tokenId);
        if (labor.animalId != MAX_UINT32)
            animals.safeTransferFrom(
                address(this),
                msg.sender,
                labor.animalId,
                1,
                ""
            );

        if (labor.supplyId != 0)
            supplies.safeTransferFrom(
                address(this),
                msg.sender,
                labor.supplyId,
                1,
                ""
            );
        if (neandersmol.staked(_tokenId))
            neandersmol.stakingHandler(_tokenId, false);
        emit LeaveLaborGround(msg.sender, _tokenId);
    }

    /**
     * @dev This function allows a user to leave the LaborGround and receive their animal, supply, and collectable.
     * @param _tokenId An array of token IDs that the user wants to leave.
     */

    function leaveLaborGround(uint256[] calldata _tokenId) external {
        uint256 i;

        for (; i < _tokenId.length; ++i) {
            uint256 tokenId = _tokenId[i];
            if (!claimCollectable(tokenId)) leaveLg(tokenId);
        }
    }

    /**
     * @dev Function to check the possible claims of an animal job
     * @param _tokenId ID of the token
     * @param labor LaborGround struct with the information of the job
     * @return consumablesTokenId The token ID of the consumables to be claimed
     */

    function checkPossibleClaims(
        uint256 _tokenId,
        LaborGround memory labor
    ) internal returns (uint256, bool) {
        uint256 rnd = randomizer.revealRandomNumber(labor.requestId) % 101;
        uint256 animalId = labor.animalId;
        uint256 consumablesTokenId;
        (uint256 tokenOne, uint256 tokenTwo) = getConsumablesTokenId(labor.job);
        bool breakTool;
        if (animalId == MAX_UINT32) {
            if (rnd < 61) {
                consumablesTokenId = tokenOne;
            } else if (rnd > 60 && rnd < 81) {
                consumablesTokenId = tokenTwo;
            } else {
                breakTool = true;
            }
        }
        if (animalId == 0) {
            if (rnd < 66) {
                consumablesTokenId = tokenOne;
            } else if (rnd > 66 && rnd < 86) {
                consumablesTokenId = tokenTwo;
            } else {
                breakTool = true;
            }
        }
        if (animalId == 1) {
            if (rnd < 66) {
                consumablesTokenId = tokenOne;
            } else if (rnd > 65 && rnd < 96) {
                consumablesTokenId = tokenTwo;
            } else {
                breakTool = true;
            }
        }
        if (animalId == 2) {
            if (rnd < 71) {
                consumablesTokenId = tokenOne;
            } else if (rnd > 70 && rnd < 96) {
                consumablesTokenId = tokenTwo;
            } else {
                return (0, false);
            }
        }
        bool broken;
        if (breakTool)
            broken = breakOrFailed(
                _tokenId,
                labor.supplyId,
                randomizer.revealRandomNumber(labor.requestId) % 2
            );

        if (animalId == 3) consumablesTokenId = rnd < 71 ? tokenOne : tokenTwo;

        if (animalId == 4) consumablesTokenId = rnd < 66 ? tokenOne : tokenTwo;

        if (animalId == 5) consumablesTokenId = rnd < 61 ? tokenOne : tokenTwo;

        return (consumablesTokenId, broken);
    }

    /**
     * @dev Function to get the consumables token IDs based on the job type
     * @param _job Job type
     * @return tokenIdOne and tokenIdTwo The token IDs of the consumables for the job
     */

    function getConsumablesTokenId(
        Jobs _job
    ) internal pure returns (uint256 tokenIdOne, uint256 tokenIdTwo) {
        if (_job == Jobs.Digging) (tokenIdOne, tokenIdTwo) = (1, 4);
        if (_job == Jobs.Foraging) (tokenIdOne, tokenIdTwo) = (2, 5);
        if (_job == Jobs.Mining) (tokenIdOne, tokenIdTwo) = (3, 6);
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

    /**
     * Handle incoming ERC1155 token transfers.
     * @dev This function is the onERC1155Received fallback function for the contract, which is triggered when the contract receives an ERC1155 token transfer.
     * @return The selector for this function, "0x20f90a7e".
     */

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function validateTokenId(
        uint256 _tokenId,
        Jobs _job
    ) internal pure returns (bool res) {
        if (_job == Jobs.Digging) return _tokenId == 1;
        if (_job == Jobs.Foraging) return _tokenId == 2;
        if (_job == Jobs.Mining) return _tokenId == 3;
    }

    /*                                                                           */
    /*                           VIEW FUNCTIONS                                  */
    /*                                                                           */

    /**
     * Retrieve information about a Labor Ground token.
     * @dev This function returns a LaborGround struct containing information about a Labor Ground token, specified by its ID, _tokenId.
     * @param _tokenId ID of the Labor Ground token to retrieve information for
     * @return lg The LaborGround struct containing information about the specified Labor Ground token.
     */

    function getLaborGroundInfo(
        uint256 _tokenId
    ) public view returns (LaborGround memory lg) {
        return laborGround[_tokenId];
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

    function getLaborGroundFeInfo(
        address _owner
    ) external view returns (LaborGroundFeInfo[] memory) {
        uint256[] memory stakedTokens = ownerToTokens[_owner];
        LaborGroundFeInfo[] memory userInfo = new LaborGroundFeInfo[](
            stakedTokens.length
        );

        uint256 i;
        for (; i < stakedTokens.length; ++i) {
            uint256 tokenId = stakedTokens[i];
            uint256 animalId = getLaborGroundInfo(tokenId).animalId;
            uint256 timeLeft = block.timestamp <
                3 days + getLaborGroundInfo(tokenId).lockTime
                ? 3 days -
                    (block.timestamp - getLaborGroundInfo(tokenId).lockTime)
                : 0;
            userInfo[i] = LaborGroundFeInfo(
                uint64(timeLeft),
                uint64(tokenId),
                uint64(animalId),
                uint64(getLaborGroundInfo(tokenId).supplyId)
            );
        }

        return userInfo;
    }

    event ClaimCollectable(address indexed owner, uint256 indexed tokenId);

    event LeaveLaborGround(address indexed owner, uint256 indexed tokenId);

    event RemoveAnimalsFromLaborGround(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed animalsId
    );

    event BringInAnimalsToLaborGround(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed animalsId
    );

    event EnterLaborGround(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed supplyId,
        Jobs job
    );
}

