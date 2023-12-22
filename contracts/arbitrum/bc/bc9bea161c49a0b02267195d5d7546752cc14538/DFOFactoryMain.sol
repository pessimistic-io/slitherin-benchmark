// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./SimpleDfoFactory.sol";

contract DFOFactoryMain is SimpleDfoFactory {

    address private dfoRegistrationOptionAddress;
    address private dfoFundraisingOptionAddress;

    function createMainWallet (string calldata _companyName, bool _isPrivate, uint _crosschainFee) public override payable returns(address){        require(!initializedCompanies[_companyName], "Company name already initialized");
        bool isParentCompany = keccak256(abi.encodePacked(_companyName)) == keccak256(abi.encodePacked(PARENT_COMPANY));
        require(msg.value == feeAmount || isParentCompany, "invalid fee value");

        address mainWallet = IMainWalletFactory(mainWalletFactoryAddress).createMainWallet(
            _companyName,
            _isPrivate,
            address(this));

        whitelistedMainWallets[mainWallet] = true;
        initializedCompanies[_companyName] = true;
        emit MainWalletCreated(_companyName, mainWallet, msg.sender);

        if(!isParentCompany){
            IDFOOption(dfoRegistrationOptionAddress).safeMint(tx.origin, 0);
        }

        return mainWallet;
    }

    function deployFundraising(Vesting.FundraisingData memory _fundraisingData, address [] memory _attachedERC20Address, uint _attachedERC20AddressLength) internal override returns(address){
        return IFundraisingFactory(fundraisingFactoryAddress).createEquityFundraising(_fundraisingData, _attachedERC20Address, _attachedERC20AddressLength);
    }

    function setRegistrationOptionAddress(address _registrationOptionAddress) external onlyOwner {
        dfoRegistrationOptionAddress = _registrationOptionAddress;
    }

    function setFundraisingOptionAddress(address _fundraisingOptionAddress) external onlyOwner {
        dfoFundraisingOptionAddress = _fundraisingOptionAddress;
    }

    function safeMint(address _sender, uint _fundraisedAmount) external {
        require(msg.sender == fundraisingFactoryAddress || msg.sender == lzContractAddress, "Not whitelisted fundraising factory address");
        if (_fundraisedAmount > 0) {
            IDFOOption(dfoFundraisingOptionAddress).safeMint(_sender, _fundraisedAmount);
        } else {
            IDFOOption(dfoRegistrationOptionAddress).safeMint(_sender, 0);
        }
    }
}


/**
 * @dev DFO Option interface to whitelist minters when company is registered and mint new option NFT's afterwards.
 */
interface IDFOOption{
    function whitelistMinters(address) external;
    function safeMint(address, uint) external;
}

