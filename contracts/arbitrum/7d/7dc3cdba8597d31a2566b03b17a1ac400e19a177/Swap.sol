// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./baseContract.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./IOracle.sol";
import {SafeMath} from "./SafeMath.sol";
import "./IUser.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract Swap is baseContract, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    address public lynkAddress;
    address public oracleAddress;
    event SwapEvent(address indexed account, uint256 amountIn,uint256 _amountOut);


    constructor(address dbContract) baseContract(dbContract) {

    }

     modifier updatePrice {
        _;
        _updateCashPrice();
    }

    function _updateCashPrice() internal {
        try IOracle(oracleAddress).update() {} catch {}
    }

    function __Swap_init() public initializer {
        __baseContract_init();
        __Swap_init_unchained();
        __ReentrancyGuard_init();
    }

    function __Swap_init_unchained() private {
    }


    function setOracleAddress(address _oracleAddress) external {
        require(_msgSender() == DBContract(DB_CONTRACT).operator());
        oracleAddress = _oracleAddress;
    }

    function setLYNKAddress(address _lynkAddress) external {
        require(_msgSender() == DBContract(DB_CONTRACT).operator());
        lynkAddress = _lynkAddress;
    }


    function getLynkPrice() public view returns(uint256) {
       
        uint8 decimals = IERC20MetadataUpgradeable(lynkAddress).decimals();

        return IOracle(oracleAddress).consult(lynkAddress,10**decimals);

    }

    function getSwapOut(uint256 _amountIn) public view returns(uint256) {

        uint256 priceInLYNK = getLynkPrice();

        uint256 _amountOut = 0;

        if(priceInLYNK>0){

            _amountOut = _amountIn.mul(1e6).div(priceInLYNK);

        }

        return _amountOut;
    }

    function swap(uint256 _amountIn) external updatePrice nonReentrant {

        address lrtAddress = DBContract(DB_CONTRACT).LRT_TOKEN();

        require(IERC20Upgradeable(lrtAddress).balanceOf(_msgSender()) >= _amountIn, 'insufficient LRT.');
    
        uint256 _amountOut = getSwapOut(_amountIn);

        require(_amountOut > 0, 'zero out');

        require(IERC20Upgradeable(lynkAddress).balanceOf(address(this)) >= _amountOut, 'insufficient LYNK.');

        _pay(lrtAddress, _msgSender(), _amountIn,IUser.REV_TYPE.LRT_ADDR);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(lynkAddress), _msgSender(), _amountOut);
        emit SwapEvent(_msgSender(),_amountIn,_amountOut);
        // AddressUpgradeable.sendValue(payable(_msgSender()), _amountOut);
    }

}

