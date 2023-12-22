// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;
import "./Ownable.sol";
import "./IERC20.sol";

abstract contract OwnerRecovery is Ownable {
    function recoverLostARB() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function recoverLostTokens(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }
}
