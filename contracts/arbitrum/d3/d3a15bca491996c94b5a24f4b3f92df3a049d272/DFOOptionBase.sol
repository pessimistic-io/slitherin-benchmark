// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./SafeMath.sol";

interface IDFOToken {
    function burn(uint) external;
    function burnFrom(address, uint) external;
    function transfer(address, uint) external;
    function transferFrom(address, address, uint) external;
    function balanceOf(address) external view returns(uint);
    function decimals() external returns(uint);
}

interface IDFOTokenPriceFeed {
    function estimateAmountOut(address, uint128, uint32) external view returns(uint);
}

interface Randomizer {
    function requestRandomWords(uint32 [] calldata _randomWordsRequest, uint32 _randomWordsRequestLength) external;
}

abstract contract DFOOptionBase is Ownable {

    using SafeMath for uint256;

    uint immutable internal executionPeriodTimestamp;
    uint immutable internal contractInitTimestamp;
    address public tokenAddress;
    uint internal constant monthlyTimestamp = 2592000;
    uint internal constant dailyTimestamp = 86400;
    address public priceFeedContractAddress;
    mapping(address => uint[]) myOptions;

    struct Option {
        address beneficiar;
        uint256 executionTimestamp;
        uint256 executionTimestampEnd;
        uint tokenId;
        bool executed;
        uint256 optionPeriod;
        uint strikePrice;
        uint fundraisedAmount;
        bool onSale;
        uint saleAmount;
    }

    address whitelisterContract;
    address optionTimestampVRF;
    mapping(address => bool) whitelistedErc20TokenAddresses;

    mapping(uint => Option) public options;
    mapping(uint => uint []) public optionsByPeriod;

    mapping(address => bool) public whitelistedMinter;

    event Executed(uint id, uint price);

    constructor(uint _executionPeriodTimestamp) {
        executionPeriodTimestamp = _executionPeriodTimestamp;
        contractInitTimestamp = block.timestamp;
    }

    function getMyOptions() public view returns(Option [] memory){
        Option[] memory newArray = new Option[](myOptions[msg.sender].length);
        for (uint i = 0; i < myOptions[msg.sender].length; i++) {
            uint optionId = myOptions[msg.sender][i];
            newArray[i] = options[optionId];
        }
        return newArray;
    }

    function setPriceFeedContractAddress(address _priceFeedContractAddress) public onlyOwner{
        priceFeedContractAddress = _priceFeedContractAddress;
    }

    function setOptionTimestampVRF(address _optionTimestampVRF) public onlyOwner {
        optionTimestampVRF = _optionTimestampVRF;
    }

    function lockupFunds(address _tokenAddress, uint _amount) public onlyOwner{
        require(tokenAddress == address(0), "Token already locked");
        tokenAddress = _tokenAddress;
        ERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
    }

    function setWhitelisterContract(address _whitelisterContract) public onlyOwner {
        whitelisterContract = _whitelisterContract;
    }

    function whitelistMinter(address _minter) public onlyOwner {
        whitelistedMinter[_minter] = true;
    }

    function whitelistMinterByWhitelister(address _contractAddress) public {
        require(msg.sender == whitelisterContract, "Not a whitelister contract");
        whitelistedMinter[_contractAddress] = true;
    }

    function whitelistErc20Token(address _erc20TokenAddress) public onlyOwner {
        whitelistedErc20TokenAddresses[_erc20TokenAddress] = !whitelistedErc20TokenAddresses[_erc20TokenAddress];
    }

    function safeMint(address to, uint _fundraisedAmount) public virtual {
    }

    function execute(uint _id, bool _buyout, address _erc20TokenAddress) public virtual {
        Option storage op = options[_id];
        require(op.beneficiar == msg.sender, "Only beneficiary can execute option");
        require(op.executed == false, "Option has been already executed");
        require(block.timestamp > op.executionTimestamp, "Execution time has not been reached yet");
        require(block.timestamp < op.executionTimestamp + dailyTimestamp, "Execution day has passed");
        require(whitelistedErc20TokenAddresses[_erc20TokenAddress], "Erc20Token address not whitelisted");

        uint amount = getOptionTokenAmount(_id);

        uint marketPrice = IDFOTokenPriceFeed(priceFeedContractAddress).estimateAmountOut(
            tokenAddress,
            1,
            0
        );

        uint erc20TokenAmount = amount * op.strikePrice;
        if(op.strikePrice >= marketPrice && _buyout){
            require (IDFOToken(_erc20TokenAddress).balanceOf(msg.sender) >= erc20TokenAmount, "Not enough balance to buyout");
            IDFOToken(_erc20TokenAddress).transferFrom(msg.sender, address(this), erc20TokenAmount);
            IDFOToken(tokenAddress).transfer(msg.sender, amount.mul(1e18));
        } else {
            IDFOToken(tokenAddress).burn(amount.mul(1e18) / 4);
        }
        op.executed = true;
        emit Executed(op.tokenId, marketPrice);
    }

    function withdrawErc20(address _erc20TokenAddress) external onlyOwner{
        ERC20(_erc20TokenAddress).transfer(msg.sender,ERC20(_erc20TokenAddress).balanceOf(address(this)));
    }

    // Chainlink automated function
    function executeUnexecutedOptions() public{
        uint optionPeriod = (block.timestamp - contractInitTimestamp - monthlyTimestamp * 6) / monthlyTimestamp;
        _executeOptions(optionPeriod);
    }

    // Chainlink automated function
    function executeUnexecutedOptionsManually(uint _optionPeriod) public onlyOwner{
        _executeOptions(_optionPeriod);
    }

    function _executeOptions(uint _optionPeriod) internal {
        for(uint i = 0; i < optionsByPeriod[_optionPeriod].length; i ++){
            uint amount = getOptionTokenAmount(options[optionsByPeriod[_optionPeriod][i]].tokenId);
            bool exe = options[optionsByPeriod[_optionPeriod][i]].executed;
            if(!exe && options[optionsByPeriod[_optionPeriod][i]].executionTimestamp < block.timestamp + dailyTimestamp ){
                options[optionsByPeriod[_optionPeriod][i]].executed = true;
                emit Executed(optionsByPeriod[_optionPeriod][i], 0);
                IDFOToken(tokenAddress).burn(amount.mul(1e18) / 4);
            }
        }
    }

    function getOptionTokenAmount(uint _id) public view virtual returns(uint){}

    function setOptionOnSale(uint _optionIdx, uint _saleAmount) public {
        Option storage option = options[_optionIdx];
        require(option.beneficiar == msg.sender, "Not an option owner to put on sale");
        option.onSale = true;
        option.saleAmount = _saleAmount;
    }

    function changeOwnership(uint _optionIdx, address _erc20TokenAddress) public {
        require(whitelistedErc20TokenAddresses[_erc20TokenAddress], "Erc20Token address not whitelisted");
        Option storage option = options[_optionIdx];
        require(option.onSale, "Option not on sale");
        require(IDFOToken(_erc20TokenAddress).balanceOf(msg.sender) >= option.saleAmount, "Not enough tokens");
        uint decimals = IDFOToken(_erc20TokenAddress).decimals();
        IDFOToken(_erc20TokenAddress).transferFrom(msg.sender, option.beneficiar, option.saleAmount ** decimals);
        option.beneficiar = msg.sender;
        option.onSale = false;
        option.saleAmount = 0;

        uint[] memory newArray = new uint[](myOptions[option.beneficiar].length - 1);
        uint newIdx = 0;
        for (uint i = 0; i < myOptions[option.beneficiar].length; i++) {
            uint optionId = myOptions[option.beneficiar][i];
            if(optionId != _optionIdx){
                newArray[newIdx] = optionId;
                newIdx++;
            }
        }
        myOptions[option.beneficiar] = newArray;

        myOptions[msg.sender].push(option.tokenId);
    }
}

