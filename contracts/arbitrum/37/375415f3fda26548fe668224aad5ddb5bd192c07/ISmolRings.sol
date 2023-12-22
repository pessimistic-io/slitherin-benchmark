// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./IERC721Enumerable.sol";

/**
 * @title  ISmolRings interface
 * @author Archethect
 * @notice This interface contains all functionalities for Smol Rings.
 */
interface ISmolRings is IERC721Enumerable {
    struct Ring {
        uint256 ringType;
    }

    function mintRing(uint256 amount, bool stake) external payable;

    function mintRingSmolSwol(
        uint256[] calldata smolIds,
        uint256[] calldata swolIds,
        bool stake
    ) external payable;

    function mintRingSmol(uint256[] calldata smolIds, bool stake) external payable;

    function mintRingSwol(uint256[] calldata swolIds, bool stake) external payable;

    function mintRingWhitelist(
        uint256 epoch,
        uint256 index,
        uint256 amount,
        uint256[] calldata rings,
        bytes32[] calldata merkleProof,
        bool stake
    ) external payable;

    function mintRingTeam(
        uint256 ringType,
        uint256 amount,
        address account
    ) external;

    function setBaseRewardFactor(uint256 baseRewardFactor_) external;

    function ringRarity(uint256 ring) external view returns (uint256);

    function getRingProps(uint256 ringId) external view returns (Ring memory);

    function getTotalRingsPerType(uint256 ringType) external view returns (uint256);

    function setRegularMintEnabled(bool status) external;

    function setWhitelistMintEnabled(bool status) external;

    function setSmolMintEnabled(bool status) external;

    function setWhitelistAmount(uint128 whitelistAmount_) external;

    function switchToRingType(uint256 ringId, uint256 ringType) external;

    function withdrawProceeds() external;
}

