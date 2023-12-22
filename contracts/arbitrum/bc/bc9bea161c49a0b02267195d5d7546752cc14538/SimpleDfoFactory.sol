// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./RevenueWallet.sol";
import "./Vesting.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

/**
 * @dev ERC20 Token factory interface to deploy ERC20token or ERC20LiabilityToken.
 */
interface IERC20TokenFactory{
    function deployToken(string memory, string memory, Vesting.VestingPlan [] memory, uint, uint) external returns(address);
    function deployLiabilityToken(string memory, string memory) external returns(address);
}

/**
 * @dev Fundraising factory interface to deploy new Fundraisings or Liability fundraisings.
 */
interface IFundraisingFactory{

    function createEquityFundraising(Vesting.FundraisingData memory, address [] memory, uint) external returns(address);
    function createLiabilityFundraising(address, address, address, bytes memory, address) external returns(address);
}

/**
 * @dev Main Wallet factory interface to deploy new instances of Main Wallet contracts for registered projects.
 */
interface IMainWalletFactory{
    function createMainWallet(string memory, bool, address) external returns(address);
}

interface ILZContract{
    function send(uint _number, address _sender, uint _crosschainFee) external payable;
}

/**
 * @dev Forcefi Factory is main contract on Forcefi structure.
 *
 * Through this contract new projects can be registered.
 * Afterwards projects can create fundraisings, deploy tokens and create revenue wallets through this contract.
 */
contract SimpleDfoFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    string constant PARENT_COMPANY = "Forcefi";
    /** @dev Fee amount that is needed to register new project */
    uint internal feeAmount;

    address internal lzContractAddress;
    address internal manager;
    address internal mainWalletFactoryAddress;
    address internal erc20LiabilityTokenFactoryAddress;
    address internal fundraisingFactoryAddress;
    address internal liabilityFactoryAddress;
    address internal successfulFundraiseFeeAddress;

    mapping(address => bool) whitelistedMainWallets;
    mapping(string => bool) public initializedCompanies;
    mapping(address => bool) internal whitelistedERC20FactoryAddresses;
    mapping(address => bool) internal whitelistedERC20InvestmentTokens;

    event FundraisingCreated(address tokenAddress, address indexed mainWalletAddress, address fundraisingAddress, bytes fundraisingData);
    event EquityFundraisingCreated(address indexed mainWalletAddress, Fundraising []);
    event TokenDeployed(string tokenName, string ticker, bool isEquity, address tokenAddress, address indexed mainWalletAddress, Vesting.VestingPlan [], uint);
    event LiabilityTokenDeployed(string tokenName, string ticker, bool isEquity, address tokenAddress, address indexed mainWalletAddress);
    event RevenueWalletCreated(string label, string description, address revenueWalletAddress, address indexed mainWalletAddress);
    event MainWalletCreated(string companyName, address mainWalletAddress, address indexed owner);

    struct Fundraising{
        Vesting.FundraisingData fundraisingData;
        address fundraisingAddress;
    }

    modifier onlyManager () {
        require(msg.sender == manager, "Not manager");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint _feeAmount, address _mainWalletFactoryAddress)
    initializer public {
        feeAmount = _feeAmount;
        mainWalletFactoryAddress = _mainWalletFactoryAddress;
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyOwner
    override
    {}

    function setLzContractAddress(address _lzContractAddress) external onlyOwner{
        lzContractAddress = _lzContractAddress;
    }

    function createMainWallet (string calldata _companyName, bool _isPrivate, uint _crosschainFee) public virtual payable returns(address){
        require(!initializedCompanies[_companyName], "Company name already initialized");
        bool isParentCompany = keccak256(abi.encodePacked(_companyName)) == keccak256(abi.encodePacked(PARENT_COMPANY));
        require(msg.value >= feeAmount || isParentCompany, "invalid fee value");
        if(isParentCompany){
            require(msg.sender == manager, "Only manager can create parent company");
        }

        address mainWallet = IMainWalletFactory(mainWalletFactoryAddress).createMainWallet(
            _companyName,
            _isPrivate,
            address(this));

        whitelistedMainWallets[mainWallet] = true;
        initializedCompanies[_companyName] = true;
        emit MainWalletCreated(_companyName, mainWallet, msg.sender);

        if(!isParentCompany){
            ILZContract(lzContractAddress).send{value: msg.value - feeAmount}(0, tx.origin, _crosschainFee);
        }

        return mainWallet;
    }

    function deployToken(string calldata _tokenName, string calldata _ticker, bool isEquity) internal returns(address){
        address tokenAddress = IERC20TokenFactory(erc20LiabilityTokenFactoryAddress).deployLiabilityToken(_tokenName, _ticker);
        emit LiabilityTokenDeployed(_tokenName, _ticker, isEquity, tokenAddress, msg.sender);
        return tokenAddress;
    }

    function createEquityFundraising(
        Vesting.TokenData calldata _tokenData,
        Vesting.VestingPlan [] memory _tokenVestingData,
        uint _tokenVestingsCount,
        Vesting.FundraisingData [] memory _fundraisingData,
        uint numOfFundraisings,
        address [] memory _attachedERC20Address,
        uint _attachedERC20AddressLength) public{
        require(whitelistedMainWallets[msg.sender], "Not whitelisted address");
        for(uint i=0; i< _attachedERC20Address.length; i++){
            require(whitelistedERC20InvestmentTokens[_attachedERC20Address[i]], "Not whitelisted ERC20 Investment Token");
        }

        if(_tokenData.isNewToken){
            deployEquityToken(_tokenData._tokenName, _tokenData._tokenTicker, _tokenVestingData, _tokenVestingsCount, _tokenData._mintAmount, _tokenData._erc20TokenFactoryAddress);
        }

        Fundraising [] memory fundraisings = new Fundraising[](numOfFundraisings);
        for(uint i=0; i<numOfFundraisings; i++){
            address fundraisingAddress = deployFundraising(_fundraisingData[i], _attachedERC20Address, _attachedERC20AddressLength);
            fundraisings[i] = Fundraising(_fundraisingData[i], fundraisingAddress);
        }
        emit EquityFundraisingCreated(msg.sender, fundraisings);

    }

    function deployEquityToken(string calldata _tokenName, string calldata _ticker, Vesting.VestingPlan [] memory _tokenVestingData, uint numOfVestings, uint _mintAmount, address _erc20TokenFactoryAddress) internal {
        require(whitelistedERC20FactoryAddresses[_erc20TokenFactoryAddress], "Not a valid ERC 20 Factory address");
        address tokenAddress = IERC20TokenFactory(_erc20TokenFactoryAddress).deployToken(_tokenName, _ticker, _tokenVestingData, numOfVestings, _mintAmount);
        emit TokenDeployed(_tokenName, _ticker, true, tokenAddress, msg.sender, _tokenVestingData, _mintAmount);
    }

    function deployFundraising(Vesting.FundraisingData memory _fundraisingData, address [] memory _attachedERC20Address, uint _attachedERC20AddressLength) internal virtual returns(address){
        return IFundraisingFactory(fundraisingFactoryAddress).createEquityFundraising(_fundraisingData, _attachedERC20Address, _attachedERC20AddressLength);
    }

    function safeMint(address _sender, uint _fundraisedAmount, uint _crosschainFee) external {
        require(msg.sender == fundraisingFactoryAddress, "Not whitelisted fundraising factory address");
        ILZContract(lzContractAddress).send(_fundraisedAmount, _sender, _crosschainFee);
    }

    function createLiabilityFundraising(address _tokenAddress, address payable _mainWalletAddress, bytes memory _fundraisingData, address _attachedERC20Address) external returns (address) {
        require(whitelistedMainWallets[msg.sender], "Not whitelisted address");
        address fundraisingAddress = IFundraisingFactory(liabilityFactoryAddress).createLiabilityFundraising(successfulFundraiseFeeAddress, _tokenAddress,  _mainWalletAddress, _fundraisingData, _attachedERC20Address);
        emit FundraisingCreated(_tokenAddress, _mainWalletAddress, fundraisingAddress, _fundraisingData);
        return fundraisingAddress;
    }

    function createRevenueWallet(address mainWalletAddress, string calldata _label, string calldata _description) public returns(address){
        require(whitelistedMainWallets[msg.sender], "Not whitelisted address");
        address revenueWallet = address(new RevenueWallet(mainWalletAddress));
        emit RevenueWalletCreated(_label, _description, revenueWallet, msg.sender);
        return revenueWallet;
    }

    /**
    @dev This function allows new ERC20 Factories to be able to create new ERC20 tokens.
    */
    function setWhitelistedERC20FactoryAddress(address _erc20TokenFactoryAddress) external onlyOwner {
        whitelistedERC20FactoryAddresses[_erc20TokenFactoryAddress] = true;
    }

    /**
    @dev Add new investment tokens for forcefi platfom.
    */
    function whitelistERC20InvestmentTokens(address _erc20TokenAddress) external onlyOwner{
        whitelistedERC20InvestmentTokens[_erc20TokenAddress] = !whitelistedERC20InvestmentTokens[_erc20TokenAddress];
    }

    function withdrawEth() external onlyManager{
        require(payable(msg.sender).send(address(this).balance));
    }

    function withdrawErc20(address _erc20TokenAddress) external onlyManager{
        ERC20(_erc20TokenAddress).transfer(msg.sender,ERC20(_erc20TokenAddress).balanceOf(address(this)));
    }

    function setMainWalletFactoryAddress(address _mainWalletFactoryAddress) external onlyOwner{
        mainWalletFactoryAddress = _mainWalletFactoryAddress;
    }

    function setErc20LiabilityTokenFactoryAddress(address _erc20LiabilityTokenFactoryAddress) external onlyOwner{
        erc20LiabilityTokenFactoryAddress = _erc20LiabilityTokenFactoryAddress;
    }

    function setFundraisingFactoryAddress(address _fundraisingFactoryAddress) external onlyOwner{
        fundraisingFactoryAddress = _fundraisingFactoryAddress;
    }

    function setFundraisingFeeAddress(address _successfulFundraiseFeeAddress) external onlyOwner {
        successfulFundraiseFeeAddress = _successfulFundraiseFeeAddress;
    }

    function setLiabilityFactoryAddress(address _liabilityFactoryAddress) external onlyOwner{
        liabilityFactoryAddress = _liabilityFactoryAddress;
    }

    function setManager(address _managerAddress) external onlyOwner {
        manager = _managerAddress;
    }

    function setFee(uint _feeAmount) external onlyManager{
        feeAmount = _feeAmount;
    }
}

