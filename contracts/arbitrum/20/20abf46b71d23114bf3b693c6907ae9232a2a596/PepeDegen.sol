//SPDX-License-Identifier:MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { DegenEpoch } from "./Structs.sol";
import { IPepeDegen } from "./IPepeDegen.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

/**
 * @title Pepe degen contract.
 * @notice This contract is used to distribute esPeg to users who have played Pepe's game and had substantial losses.
 */
contract PepeDegen is IPepeDegen, Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 public immutable esPegToken;

    uint32 public currentEpoch;

    mapping(uint32 epochId => mapping(address user => uint256 amount)) public claimableAmount;
    mapping(address user => uint256 amount) public amountClaimed;
    mapping(uint32 epochId => bool enabled) public claimEnabled;
    mapping(uint32 epochId => DegenEpoch) public epochDetails;

    event CanClaim(uint32 indexed epochId, address indexed user, uint256 amount);
    event Claimed(uint32 indexed epochId, address indexed user, uint256 amount);
    event Retrieved(address indexed token, uint256 amount);
    event ClaimEnabled(uint32 indexed epochId);
    event ClaimDisabled(uint32 indexed epochId);

    constructor(address _esPegToken) {
        esPegToken = IERC20(_esPegToken);
    }

    ///@param _users array of addresses to set claimable amount for
    ///@param _claimableAmount array of claimable amounts for each user
    function setRecipients(address[] calldata _users, uint256[] calldata _claimableAmount) external override onlyOwner {
        require(_users.length == _claimableAmount.length, "invalid array length");
        uint32 _epochId = ++currentEpoch;

        uint256 sum;
        uint256 arrayLength = _users.length;
        uint256 i;
        for (; i < arrayLength; ) {
            require(_users[i] != address(0), "zero address");
            require(_claimableAmount[i] != 0, "zero amount");
            claimableAmount[_epochId][_users[i]] += _claimableAmount[i];

            emit CanClaim(_epochId, _users[i], _claimableAmount[i]);

            unchecked {
                sum += _claimableAmount[i];
                ++i;
            }
        }

        require(esPegToken.balanceOf(address(this)) >= sum, "insufficient esPeg balance");
        epochDetails[_epochId] = DegenEpoch({ epochId: _epochId, users: _users, amounts: _claimableAmount });
    }

    ///@param _epochId claim esPeg tokens for a specific epoch
    function claim(uint32 _epochId) external override {
        DegenEpoch memory epoch = epochDetails[_epochId];
        require(epoch.epochId != 0, "epoch not found");
        require(claimEnabled[_epochId], "claim not enabled");

        uint256 amount = claimableAmount[_epochId][msg.sender];

        if (amount != 0) {
            claimableAmount[_epochId][msg.sender] = 0;
            amountClaimed[msg.sender] += amount;

            esPegToken.safeTransfer(msg.sender, amount);

            emit Claimed(_epochId, msg.sender, amount);
        }
    }

    ///@notice claim all esPeg tokens for all epochs
    function claimAll() external override {
        uint32 i;
        for (; i <= currentEpoch; ) {
            if (claimEnabled[i]) {
                uint256 amount = claimableAmount[i][msg.sender];
                if (amount != 0) {
                    claimableAmount[i][msg.sender] = 0;
                    amountClaimed[msg.sender] += amount;

                    esPegToken.safeTransfer(msg.sender, amount);

                    emit Claimed(i, msg.sender, amount);
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function enableClaim(uint32 epochId) external override onlyOwner {
        claimEnabled[epochId] = true;
        emit ClaimEnabled(epochId);
    }

    function disableClaim(uint32 epochId) external override onlyOwner {
        claimEnabled[epochId] = false;
        emit ClaimDisabled(epochId);
    }

    function totalClaimable(address _user) external view override returns (uint256) {
        uint32 i;
        uint256 sum;
        for (; i <= currentEpoch; ) {
            sum += claimableAmount[i][_user];
            unchecked {
                ++i;
            }
        }
        return sum;
    }

    function retrieve(address token) external override onlyOwner {
        require(token != address(esPegToken), "cannot retrieve esPeg");

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            (bool success, ) = payable(owner()).call{ value: ethBalance }("");
            require(success, "ETH retrival failed");
        }

        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Retrieved(token, amount);
    }
}

