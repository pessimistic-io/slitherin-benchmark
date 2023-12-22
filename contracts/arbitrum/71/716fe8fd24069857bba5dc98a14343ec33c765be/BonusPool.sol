// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract BonusPool is UUPSUpgradeable, OwnableUpgradeable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _callers;
    address public tokenAddress;

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize( address token_) external initializer {
        __Ownable_init();
        tokenAddress = token_;
    }
    function injectRewards(uint256 amount) public onlyCaller {
        IERC20(tokenAddress).safeTransferFrom(_msgSender(), address(this), amount);
    }

    function rescueToken(address _tokenAddress) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(msg.sender,IERC20(_tokenAddress).balanceOf(address(this)));
    }

    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(new bytes(0));
        require(success, 'BonusPool: ETH_TRANSFER_FAILED');
    }


    function addCaller(address val) public onlyOwner() {
        require(val != address(0), "BonusPool: val is the zero address");
        _callers.add(val);
    }

    function delCaller(address caller) public onlyOwner returns (bool) {
        require(caller != address(0), "BonusPool: caller is the zero address");
        return _callers.remove(caller);
    }
    function getCallers() public view returns (address[] memory ret) {
        return _callers.values();
    }

    modifier onlyCaller() {
        require(_callers.contains(_msgSender()), "onlyCaller");
        _;
    }
}

