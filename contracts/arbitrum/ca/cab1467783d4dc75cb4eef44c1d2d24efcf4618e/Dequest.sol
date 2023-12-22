// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./AccessControl.sol";
import "./IERC20.sol";
import "./IERC1155.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ECDSA.sol";

contract Dequest is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /**
     * @notice Validator role hash.
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @notice Validator role hash.
     */
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    /**
     * @notice validator address.
     */
    address public validator;

    /**
     * @notice number used only once for validation.
     */
    mapping(bytes32 => bool) public ERC20_ids;
    mapping(bytes32 => bool) public ERC1155_ids;

    /**
     * @notice emmited when user claims reward
     *
     * @param id id of claim
     * @param user user address
     * @param token token address
     * @param value amount of user rewards
     */
    event ClaimedERC20(address user, uint256 value, string id, address token);
    event ClaimedERC1155(address user, uint256[] _nftIds, uint256[] value, string id, address token);

    /**
     * @notice Initializes a new instance of the Dequest contract.
     *
     * @param _validator address that is allowed to sign data.
     */
    constructor(address _validator) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(VALIDATOR_ROLE, ADMIN_ROLE);
        _setupRole(VALIDATOR_ROLE, _validator);
        validator = _validator;
    }

    /**
     * @notice Sends reward to msg sender.
     *
     * @param _value token amount to be claimed.
     * @param _id unique identifier sent by backend
     * @param _token token address to be sent
     * @param v component of ECDSA.
     * @param r component of ECDSA.
     * @param s component of ECDSA.
     */
    function claimERC20(
        uint256 _value,
        string memory _id,
        address _token,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        bytes32 message = keccak256(
            abi.encodePacked(msg.sender, _value, _id, _token)
        ); 
        require(
            ERC20_ids[message] == false,
            "Transaction was already processed"
        );
        require(
            hasRole(
                VALIDATOR_ROLE,
                message.toEthSignedMessageHash().recover(v, r, s)
            ),
            "Validator address is invalid"
        );
        IERC20(_token).safeTransfer(msg.sender, _value);
        ERC20_ids[message] = true;
        emit ClaimedERC20(msg.sender, _value, _id, _token);
    }

    function claimERC1155(
        uint256[] memory _nftIds,
        uint256[] memory _values,
        string memory _id,
        address _token,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        bytes32 message = keccak256(
            abi.encodePacked(msg.sender, _nftIds, _values, _id, _token)
        );
        require(
            ERC1155_ids[message] == false,
            "Transaction was already processed"
        );
        require(
            hasRole(
                VALIDATOR_ROLE,
                message.toEthSignedMessageHash().recover(v, r, s)
            ),
            "Validator address is invalid"
        );
        IERC1155(_token).mintBatch(msg.sender, _nftIds, _values, "");
        ERC1155_ids[message] = true;
        emit ClaimedERC1155(msg.sender, _nftIds, _values, _id, _token);
    }

    /**
     * @notice changes validator address.
     */
    function changeValidator(address _newValidator)
        external
        onlyRole(ADMIN_ROLE)
    {
        revokeRole(VALIDATOR_ROLE, validator);
        grantRole(VALIDATOR_ROLE, _newValidator);
        validator = _newValidator;
    }
}

