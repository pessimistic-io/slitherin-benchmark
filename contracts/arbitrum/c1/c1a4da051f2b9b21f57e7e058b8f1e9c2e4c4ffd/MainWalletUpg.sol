// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./Initializable.sol";
import "./Ownable.sol";
import "./RevenueWallet.sol";
import "./Vesting.sol";

interface IDFOFactory {

    function deployToken(string memory, string memory, bool) external returns(address);
    function createEquityFundraising(Vesting.TokenData calldata, Vesting.VestingPlan [] memory, uint, Vesting.FundraisingData[] calldata, uint, address [] memory, uint) external;
    function createLiabilityFundraising(address, address, bytes memory, address) external returns (address);
    function createRevenueWallet(address, string calldata, string calldata) external returns(address);
}

interface IERC20Token {
    function mint(uint) external;
}

contract MainWalletUpg is Ownable, Initializable{

    string public companyName;
    bool public isPrivateCompany;

    event WithdrawalProcessed(address mainWalletAddress, address tokenAddress, address recipient, uint amount);

    address public developerAddress;

    function initialize(string memory _companyName, bool _isPrivate, address _developerAddress) external initializer{
        _transferOwnership(tx.origin);
        companyName = _companyName;
        developerAddress = _developerAddress;
        isPrivateCompany = _isPrivate;
    }

    function createRevenueWallet(string memory _label, string memory _description) public onlyOwner {
        _createRevenueWallet(_label, _description);
    }

    function _createRevenueWallet(string memory _label, string memory _description) private {
        IDFOFactory(developerAddress).createRevenueWallet(address(this), _label, _description);
    }

    function createEquityFundraising(Vesting.VestingPlan [] memory _tokenVestingData,
        uint _tokenVestingsCount,
        Vesting.TokenData calldata _tokenData,
        Vesting.FundraisingData [] memory _fundraisingData,
        uint _numOfFundraisings,
        address [] memory _attachedERC20Address,
        uint _attachedERC20AddressLength) public onlyOwner{
        IDFOFactory(developerAddress).createEquityFundraising(_tokenData, _tokenVestingData, _tokenVestingsCount, _fundraisingData, _numOfFundraisings, _attachedERC20Address, _attachedERC20AddressLength);
    }

    function createLiabilityFundraising(string memory _tokenName, string memory _tokenTicker, bytes memory _fundraisingData, address _attachedERC20Address) public onlyOwner returns(address){
        address liabilityTokenAddress = _deployToken(_tokenName, _tokenTicker, false);
        return IDFOFactory(developerAddress).createLiabilityFundraising(liabilityTokenAddress, address(this), _fundraisingData, _attachedERC20Address);
    }

    function _deployToken(string memory _name, string memory _ticker, bool _isEquity) internal returns(address) {
        return IDFOFactory(developerAddress).deployToken(_name, _ticker, _isEquity);
    }

    function withdrawToken(address _tokenContract, address _recipient, uint256 _amount) external onlyOwner{
        IERC20(_tokenContract).transfer(_recipient, _amount);
        emit WithdrawalProcessed(address(this), _tokenContract, _recipient, _amount);
    }
}

