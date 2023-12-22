//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title Token Distributor contract.
 * @dev Distributes various tokens to users.
 */
import { Ownable2Step } from "./Ownable2Step.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract TokenDistributor is Ownable2Step {
    using SafeERC20 for IERC20;

    mapping(address token => uint256 amount) public totalClaimable;
    mapping(address token => mapping(address user => uint256 amount)) public claimableAmount;
    mapping(address token => mapping(address user => uint256 amount)) public amountClaimed;
    mapping(address token => bool) public claimEnabled;

    event CanClaim(address indexed token, address indexed recipient, uint256 amount);
    event Claimed(address indexed token, address indexed recipient, uint256 amount);
    event ClaimEnabled(address indexed token, bool indexed canClaim);
    event ClaimDisabled(address indexed token, bool indexed canClaim);
    event Retrieved(address indexed token, uint256 amount);

    function setRecipients(
        address token,
        address[] calldata _recipients,
        uint256[] calldata _claimableAmount
    ) external onlyOwner {
        require(token != address(0), "zero address");
        require(_recipients.length == _claimableAmount.length, "invalid array length");

        uint256 sum = totalClaimable[token];
        uint256 arrayLength = _recipients.length;
        uint256 i;
        for (; i < arrayLength; ) {
            require(_recipients[i] != address(0), "zero address");
            require(_claimableAmount[i] != 0, "zero amount");
            claimableAmount[token][_recipients[i]] += _claimableAmount[i];

            emit CanClaim(token, _recipients[i], _claimableAmount[i]);

            unchecked {
                sum += _claimableAmount[i];
                ++i;
            }
        }

        require(IERC20(token).balanceOf(address(this)) >= sum, "not enough token balance");
        totalClaimable[token] = sum;
    }

    function claim(address token) public {
        require(claimEnabled[token], "claim not started");

        uint256 amount = claimableAmount[token][msg.sender];
        require(amount != 0, "nothing to claim");

        claimableAmount[token][msg.sender] = 0;

        IERC20(token).safeTransfer(msg.sender, amount);
        amountClaimed[token][msg.sender] += amount;

        emit Claimed(token, msg.sender, amount);
    }

    function retrieve(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            (bool success, ) = payable(owner()).call{ value: ethBalance }("");
            require(success, "Retrieval Failed");
            emit Retrieved(address(0), ethBalance);
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
        emit Retrieved(_token, token.balanceOf(address(this)));
    }

    function enableClaim(address token) external onlyOwner {
        claimEnabled[token] = true;
        emit ClaimEnabled(token, claimEnabled[token]);
    }

    function disableClaim(address token) external onlyOwner {
        claimEnabled[token] = false;
        emit ClaimDisabled(token, claimEnabled[token]);
    }
}

