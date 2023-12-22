// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./IERC20.sol";
import "./Address.sol";
import {IToken} from "./IToken.sol";

abstract contract SupportToken is AccessControl {
    mapping(address => bool) public blackListWallet;
    mapping(address => bool) public whiteListAddressBot;

    bool public enableWhiteListBot = false;
    bool public enableSell = true;
    bool public isEnable = true;
    address public investmentContract;
    address public airdropContract;

    mapping(address => bool) public enableSellAddress;

    event SetInvestmentContract(address newAddress, address oldAddress);
    event SetAirdropContract(address newAddress, address oldAddress);

    /**
	Set enable whitelist bot
	*/
    function setEnableWhiteListBot(bool _result) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        enableWhiteListBot = _result;
    }

    /**
	Set enable check Investment , Airdrop contract
	*/
    function setEnable(bool _result) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        isEnable = _result;
    }

    /**
	Set blacklist wallet can not transfer token
	*/
    function setBlackListWallet(address[] memory _address, bool result) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        for (uint256 i = 0; i < _address.length; i++) {
            blackListWallet[_address[i]] = result;
        }
    }

    /**
	Set whitelist bot can transfer token
	*/
    function setWhiteListAddressBot(
        address[] memory _address,
        bool result
    ) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        for (uint256 i = 0; i < _address.length; i++) {
            whiteListAddressBot[_address[i]] = result;
        }
    }

    function clearUnknownToken(address _tokenAddress) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        uint256 contractBalance = IERC20(_tokenAddress).balanceOf(
            address(this)
        );
        IERC20(_tokenAddress).transfer(address(msg.sender), contractBalance);
    }

    function isContract(address account) internal view returns (bool) {
        return Address.isContract(account);
    }

    /**
	set is investment contract
	*/
    function setInvestmentContract(address _investmentContract) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        emit SetInvestmentContract(_investmentContract, investmentContract);
        investmentContract = _investmentContract;
    }

    /**
	set is airdrop contract
	*/
    function setAirdropContract(address _airdropContract) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        emit SetAirdropContract(_airdropContract, airdropContract);
        airdropContract = _airdropContract;
    }

    function checkTransfer(address account) public view returns (uint256) {
        uint256 amount = 0;
        if (investmentContract != address(0)) {
            amount += IToken(investmentContract).getITransferInvestment(
                account
            );
        }
        if (airdropContract != address(0)) {
            amount += IToken(airdropContract).getITransferAirdrop(account);
        }
        return amount;
    }

    function setEnableSell(bool _result) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        enableSell = _result;
    }

    function setEnableSellAddress(address _address, bool _result) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Matrix: not have permission"
        );
        enableSellAddress[_address] = _result;
    }
}

