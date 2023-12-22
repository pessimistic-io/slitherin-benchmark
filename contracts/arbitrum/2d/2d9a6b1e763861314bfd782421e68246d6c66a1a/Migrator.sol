// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./MerkleProof.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract Migrator is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public merkleRoot;
    IERC20Upgradeable public moSOLID;

    uint256 public totalClaimedAmount;
    mapping(address => uint256) public claimedAmount;

    event ClaimMoSOLID(address user, uint256 amount, uint256 claimableAmount);

    error InvalidProof();
    error AlreadyClaimed();

    function initialize(
        bytes32 _merkleRoot,
        address _moSOLID,
        address _setter,
        address _admin
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(SETTER_ROLE, _setter);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        merkleRoot = _merkleRoot;

        moSOLID = IERC20Upgradeable(_moSOLID);
    }

    function pause() public onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyRole(SETTER_ROLE) {
        merkleRoot = _merkleRoot;
    }

    function claimMoSOLID(uint256 amount, bytes32[] memory proof)
        external
        whenNotPaused
    {
        if (
            !MerkleProof.verify(
                proof,
                merkleRoot,
                keccak256(abi.encode(msg.sender, amount))
            )
        ) revert InvalidProof();

        uint256 claimableAmount = amount - claimedAmount[msg.sender];
        if (claimableAmount > 0) {
            claimedAmount[msg.sender] += claimableAmount;
            totalClaimedAmount += claimableAmount;
            moSOLID.transfer(msg.sender, claimableAmount);

            emit ClaimMoSOLID(msg.sender, amount, claimableAmount);
        } else {
            revert AlreadyClaimed();
        }
    }
}

