// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {IUniswapV2Pool} from "./IUniswapV2Pool.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";



contract Draco is ERC20 {

    error VaultAlreadySet();
    error Unauthorized();
    error DrsAlreadySet();



    address public  drs; // Jimmy Revenue Service (DRS) address
    address public vault; // uDraco vault address
    address public immutable controller; 

    // in 10ths of a percent because of the .5% DRS_FEE
    uint256 public constant BUY_BURN_FEE = 40;
    uint256 public constant SELL_BURN_FEE = 25;
    uint256 public constant SELL_STAKER_FEE = 20;
    uint256 public constant DRS_FEE = 5;

    uint256 internal constant PRECISION = 1e18;
    uint256 public constant INITIAL_TOTAL_SUPPLY = 100000000 * 1e18;


    constructor() ERC20("DRACO", "DRACO", 18) {
        // Mint initial supply to controller
        controller = msg.sender;
        _mint(msg.sender, INITIAL_TOTAL_SUPPLY);
    }


    function setVault(address vault_) external {
        if (msg.sender != controller) revert Unauthorized();
        if (vault != address(0)) revert VaultAlreadySet();
        vault = vault_;
    }
    function setDrs(address drs_) external {
        if (msg.sender != controller) revert Unauthorized();
        if (drs != address(0)) revert DrsAlreadySet();
        drs = drs_;
    }

    /// -----------------------------------------------------------------------
    /// OVERRIDES
    /// -----------------------------------------------------------------------
    function transfer(
        address to_,
        uint256 amount_
    ) public virtual override returns (bool) {
        balanceOf[msg.sender] -= amount_;

        uint256 totalTax;

        if (_isUniV3Pool(to_) || _isUniV2Pair(to_)) {

            totalTax  = _chargeTax(msg.sender, amount_);

        }    

        uint256 _toAmount = amount_ - totalTax;

        unchecked {
            balanceOf[to_] += _toAmount;
        }

        emit Transfer(msg.sender, to_, _toAmount);

        return true;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) public virtual override returns (bool) {

        // Saves gas for limited approvals.
        uint256 allowed = allowance[from_][msg.sender];
    
        if (allowed != type(uint256).max){
            require(allowed >= amount_);
            allowance[from_][msg.sender] = allowed - amount_;
        }

        balanceOf[from_] -= amount_;

        uint256 totalTax;

        if (_isUniV3Pool(to_) || _isUniV2Pair(to_)) {

            totalTax  = _chargeTax(msg.sender, amount_);

        }       

        uint256 _toAmount = amount_ - totalTax;

        unchecked {
            balanceOf[to_] += _toAmount;
        }

        emit Transfer(from_, to_, _toAmount);

        return true;
    }

    /// -----------------------------------------------------------------------
    /// TAX LOGIC
    /// -----------------------------------------------------------------------

    function chargeTax(
        address from,
        uint256 amount
    ) external returns (uint256 totalTax) {

        return _chargeTax(from,amount);

    }

    function _chargeTax(
        address from,
        uint256 amount
    ) private returns (uint256 totalTax) {

        uint256 _amount = amount;
       
        uint256 drsFee = _calculateFee(_amount, DRS_FEE);
        uint256 burn = _calculateFee(_amount, SELL_BURN_FEE);
        uint256 sendToVault = _calculateFee(_amount, SELL_STAKER_FEE);

        balanceOf[drs] += drsFee;

        emit Transfer(from, drs, drsFee);

        balanceOf[vault] += sendToVault;
        emit Transfer(from, vault, sendToVault);

        unchecked {
            totalSupply -= burn;
        }
        emit Transfer(from, address(0), burn);

        return drsFee + sendToVault + burn;
    }

    function tempChargeTax(
        address from,
        uint256 amount
    ) external returns (uint256 totalTax) {

        uint256  _amount = amount;

        totalTax = _calculateTotalTax(_amount);
         
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max){
            require(allowed >= totalTax);
            allowance[from][msg.sender] = allowed - totalTax;
        }
        balanceOf[from] -= totalTax;
        balanceOf[msg.sender] += totalTax;

        emit Transfer(from, msg.sender, totalTax);

    }

    function backTax(
        address to,
        uint256 amountTaxBack,
        uint256 amountTax
    ) external returns (uint256 totalTax) {

        uint256  _amountTaxBack = amountTaxBack* 100/95;

        uint256 _amountTax = amountTax* 100/95;

        totalTax = _calculateTotalTax(_amountTaxBack);

        _chargeTax(msg.sender,_amountTax);
      
        balanceOf[to] += totalTax;
        
        emit Transfer(msg.sender, to, totalTax);

    }

    function calculateTotalTax(
        uint256 amount
    ) external pure returns (uint256 taxAmount) {

        return _calculateTotalTax(amount);
    }

    function _calculateTotalTax(
        uint256 amount
    ) internal pure  returns (uint256 taxAmount) {

        uint256 drsFee = _calculateFee(amount, DRS_FEE);
        uint256 burn = _calculateFee(amount, SELL_BURN_FEE);
        uint256 sendToVault = _calculateFee(amount, SELL_STAKER_FEE);
        
        return drsFee + burn + sendToVault;
    }


    /// -----------------------------------------------------------------------
    /// MORE HELPERS AND VIEW FUNCS
    /// -----------------------------------------------------------------------

    function _calculateFee(
        uint256 amount,
        uint256 pct
    ) internal pure returns (uint256) {
        uint256 feePercentage = (PRECISION * pct) / 1000; // x pct
        return (amount * feePercentage) / PRECISION;
    }
    function _isUniV3Pool(address target) internal view returns (bool) {
        if (target.code.length == 0) return false;

        IUniswapV3Pool pool = IUniswapV3Pool(target);

        try pool.token0() {} catch (bytes memory) {
            return false;
        }

        try pool.token1() {} catch (bytes memory) {
            return false;
        }

        try pool.fee() {} catch (bytes memory) {
            return false;
        }

        return true;
    }

    function _isUniV2Pair(address target) internal view returns (bool) {
        if (target.code.length == 0) return false;

        IUniswapV2Pool uniPair = IUniswapV2Pool(target);

        try uniPair.token0() {} catch (bytes memory) {
            return false;
        }

        try uniPair.token1() {} catch (bytes memory) {
            return false;
        }

        try uniPair.kLast() {} catch (bytes memory) {
            return false;
        }

        return true;
    }
}

