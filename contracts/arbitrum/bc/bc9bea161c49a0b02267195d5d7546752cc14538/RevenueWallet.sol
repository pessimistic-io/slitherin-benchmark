// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./Ownable.sol";
import "./ERC20.sol";

contract RevenueWallet is Ownable{

    address immutable private mainWalletAddress;

    constructor(address _mainWalletAddress){
        mainWalletAddress = _mainWalletAddress;
        _transferOwnership(tx.origin);
    }

    event WithdrawalProcessed(address mainWalletAddress, address revenueWalletAddress, address tokenAddress, address recipient, uint amount);

    function withdrawToken(address _tokenContract, address _recipient, uint256 _amount) external onlyOwner{
        ERC20(_tokenContract).transfer(_recipient, _amount);
        emit WithdrawalProcessed(mainWalletAddress, address(this), _tokenContract, _recipient, _amount);
    }
}

