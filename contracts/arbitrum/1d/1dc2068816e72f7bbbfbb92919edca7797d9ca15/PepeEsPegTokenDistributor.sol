//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IPepeEsPegTokenDistributor } from "./IPepeEsPegTokenDistributor.sol";

contract PepeEsPegTokenDistributor is IPepeEsPegTokenDistributor, Ownable2Step {
    using SafeERC20 for IERC20;
    IERC20 public immutable esPegToken;

    uint256 public totalClaimable;
    bool public claimEnabled;

    mapping(address user => uint256 amount) public claimableAmount;

    event CanClaim(address indexed recipient, uint256 amount);
    event Claimed(address indexed recipient, uint256 amount);
    event ClaimEnabled(bool indexed canClaim);

    constructor(address _esPegToken) {
        esPegToken = IERC20(_esPegToken);
    }

    function setRecipients(address[] calldata _recipients, uint256[] calldata _claimableAmount) external onlyOwner {
        require(_recipients.length == _claimableAmount.length, "invalid array length");
        uint256 sum = totalClaimable;

        uint256 i;
        for (; i < _recipients.length; ) {
            require(_recipients[i] != address(0), "zero address");
            require(_claimableAmount[i] != 0, "zero amount");
            require(claimableAmount[_recipients[i]] == 0, "recipient already set");
            claimableAmount[_recipients[i]] = _claimableAmount[i];

            emit CanClaim(_recipients[i], _claimableAmount[i]);
            unchecked {
                sum += _claimableAmount[i];
                ++i;
            }
        }

        require(esPegToken.balanceOf(address(this)) >= sum, "not enough esPeg balance");
        totalClaimable = sum;
    }

    function enableClaim() external onlyOwner {
        claimEnabled = true;
        emit ClaimEnabled(claimEnabled);
    }

    function disableClaim() external onlyOwner {
        claimEnabled = false;
        emit ClaimEnabled(claimEnabled);
    }

    function claim() public {
        require(claimEnabled, "claim not started");

        uint256 amount = claimableAmount[msg.sender];
        require(amount != 0, "nothing to claim");

        claimableAmount[msg.sender] = 0;

        require(esPegToken.transfer(msg.sender, amount), "esPeg transfer failed");
        emit Claimed(msg.sender, amount);
    }

    function getClaimableAmount(address _user) external view returns (uint256) {
        return claimableAmount[_user];
    }

    function getTotalClaimable() external view returns (uint256) {
        return totalClaimable;
    }

    function retrieve(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "Retrieval Failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}

