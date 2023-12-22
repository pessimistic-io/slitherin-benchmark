// SPDX-License-Identifier: MIT
pragma solidity ^ 0.8;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./IERC20Metadata.sol";
import "./EnumerableSet.sol";

contract MomoLockupTool is Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    IERC20 public targetToken;
    address public daoWallet;// unlock into dao
    EnumerableSet.AddressSet private _callers;

    uint public unlockTime;    //1758297600

    event UnlockEvent(uint amount, uint when);

    constructor(IERC20 token_, address wallet_, uint unlockTime_) {
        require(
            block.timestamp < unlockTime_,
            "Unlock time should be in the future"
        );

        targetToken = IERC20(token_);

        daoWallet = wallet_;
        unlockTime = unlockTime_;
    }

    function unlock() public onlyCaller {

        require(block.timestamp >= unlockTime, "Can't unlock yet");

        uint256 amount = targetToken.balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        targetToken.transfer(daoWallet, amount);
        emit UnlockEvent(amount, block.timestamp);       
    }


    function addCaller(address val) public onlyOwner {
        require(val != address(0), "val is the zero address");
        _callers.add(val);
    }

    function delCaller(address caller) public onlyOwner returns (bool) {
        require(caller != address(0), "caller is the zero address");
        return _callers.remove(caller);
    }

    function getCallers() public view returns (address[] memory ret) {
        return _callers.values();
    }

    modifier onlyCaller() {
        require(_callers.contains(_msgSender()), "onlyCaller");
        _;
    }

    receive() external payable {}

}
