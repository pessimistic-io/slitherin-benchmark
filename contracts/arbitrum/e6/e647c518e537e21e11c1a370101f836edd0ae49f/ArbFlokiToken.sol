// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./ERC20.sol";

import "./SafeMath.sol";
import "./ERC20Burnable.sol";

contract ArbFlokiToken is ERC20, Ownable, ERC20Burnable {
    using SafeMath for uint256;

    string public constant _name = "Arb Floki";
    string public constant _symbol = "AIFLOKI";
    uint8 public constant _decimals = 18;

    uint256 TRANSACTION_TAX_FEE = 15; //5 percent
    address public constant CARMELOT_LP_WALLET = 0x6E619266E3D648EB96D0A31072c9A24bAc10D7bB;
    address public constant TAX_WALLET = 0x54D4f416045F1F6BAfc53465bc62D9c0Ab713a04 ;
    address public constant DEV_TEAM_WALLET = 0xC9BFcB2e04c129dDD3EC713A5EA0AF038A305f61;
    address LP_REWARD_WALLET = 0x75d3996Cf7dCaeC822b775382E0301C1e49a9517;
    address LP_TO_ADD_BACK_WALLET = 0x6503aab2a00AC59f995c45a5b0E6A4Fa0544e153;
    address EARN_WALLET = 0x253d6BDceFed5A331a2d302c2e4E04dec83D9552;
    address public constant BURN_WALLET = 0x000000000000000000000000000000000000dEaD;

    uint256 private LAUNCH_TIME;


    uint256 public constant TOKEN_SUPPLY = 210000000000000000; // 1 Billion
    uint256 public TOKEN_CLAIMED = 0;
    
    //Liquidity
    uint256 public constant LIQ_TOKEN_SUPPLY = 210000000000000000; //90%
    uint256 private LIQ_TOKEN_CLAIMED = 0;
    address private LIQ_WALLET_ADDRESS = 0x7c1e1506D1eAd549fCc03fc8Dc31B077c24528D0;
    //a mapping to determine which contract has access to write data to this contract
    //used in the modifier below
    mapping(address => bool) accessAllowed;
    //function modifier checks to see if an address has permission to update data
    //bool has to be true
    modifier isAllowed() {
        require(accessAllowed[msg.sender] == true);
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        _;
    }

    bool inSwap = false;

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() ERC20(_name, _symbol) {
        //Set Launch time
        LAUNCH_TIME = block.timestamp;

        accessAllowed[msg.sender] = true;
        accessAllowed[TAX_WALLET] = true;


        accessAllowed[DEV_TEAM_WALLET] = true;
        accessAllowed[LP_REWARD_WALLET] = true;
        accessAllowed[EARN_WALLET] = true;
        accessAllowed[CARMELOT_LP_WALLET] = true;
    }

    function setup_wallets (
        address _liq_wallet_address

    )
    

    public isAllowed returns (bool) {
        LIQ_WALLET_ADDRESS = _liq_wallet_address;
        return true;

    }

    function setupTaxFee(uint256 _taxValue) public onlyOwner returns (uint256){
        //setup the tax percent
        if(_taxValue > 0 ) {
            TRANSACTION_TAX_FEE = _taxValue;
        }
        return TRANSACTION_TAX_FEE;
        
    }

    function setup_wallet(address _address) public onlyOwner returns (bool){
        accessAllowed[_address] = true;
        return true;
    }

    function setupLiquidityRewardWallet(address _liquidityRewardWallet) public onlyOwner returns (address){
        //setup the tax percent
        LP_REWARD_WALLET = _liquidityRewardWallet;
        return LP_REWARD_WALLET;
    }

    function setupEarnWallet(address _earnWallet) public onlyOwner returns (address) {
        EARN_WALLET = _earnWallet;
        return EARN_WALLET;
    }
    

    function get_available_unlocked_token_amount(
        uint256 _total_supply,
        uint256 _minted_qty,
        uint256 tge,
        uint256 cliff_months,
        uint256 vesting_months
    ) internal view returns (uint256) {
        //Available Qty Initial value: 0
        uint256 available_qty = 0;

        uint256 tge_qty = tge * _total_supply/100; // tge = 0%, 10%, 50%

        //Available Qty value: Add TGE
        available_qty += tge_qty;

        if (available_qty == _total_supply) {
            return available_qty;
        }

        // If Available Qty == Total Qty , Return the value

        if (available_qty < _total_supply && vesting_months > 0) {
            //Calculating cliffing
            uint256 months_since_deployment = (block.timestamp - LAUNCH_TIME)
                .div(30 * 24 * 60 * 60); // 1 month = 30 days

            if (months_since_deployment > cliff_months) {
                uint256 months_since_cliffing_time = months_since_deployment -
                    cliff_months;
                //Available Qty value: Add Cliffing value by month
                available_qty += (_total_supply - tge_qty)
                    .mul(months_since_cliffing_time).div(vesting_months);

                if (months_since_cliffing_time >= vesting_months) {
                    //Available Qty value: All all supply qty if vesting month pass.
                    available_qty = _total_supply;
                }
            }
        }
        //Available Qty value: Subtract the minted quantity
        available_qty -= _minted_qty;

        return available_qty;
    }
    function liq_withdraw() public onlyOwner returns (uint256) {
        //require(msg.sender == LIQ_WALLET_ADDRESS, "Not authorized!");

        //100% unlocked
        uint256 available_qty = get_available_unlocked_token_amount(
            LIQ_TOKEN_SUPPLY,
            LIQ_TOKEN_CLAIMED,
            100,
            0,
            0
        );

        require(available_qty > 0, "Token is not available!");

        LIQ_TOKEN_CLAIMED += available_qty;
        TOKEN_CLAIMED += available_qty;

        _mint(msg.sender, available_qty * (10**_decimals));

        return available_qty;
    }


    function totalSupply() public pure override returns (uint256) {
        return TOKEN_SUPPLY * (10**_decimals);
    }


    function transfer(address to, uint256 value) public virtual override returns (bool){
        //Call local function
        return _transferFrom(msg.sender, to, value);
    }


    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override returns (bool){

        //Call parent functions to spend allowance
        address spender = _msgSender();
        _spendAllowance(from, spender, value);

        // Call local transferFrom
        return _transferFrom(from, to, value);

    }


   
    function shouldTakeFee(address from, address to, uint256 amount)
        internal
        view
        returns (bool)
    {
        return !(accessAllowed[from] && amount > 0);
    }


    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        

        uint256 taxFee = 0;

        if (shouldTakeFee(sender,recipient, amount)){
            taxFee = amount.mul(TRANSACTION_TAX_FEE).div(100);

        }
        uint256 netAmount = amount - taxFee;

        if(taxFee>0){
            // Call local transferFrom
            //_transfer(sender, TAX_WALLET, taxFee);
            /**
             * 3% to dev eam
             * 3% to LP reward
             * 2% add back to the liquidity
             * 1% to earn and reward
             * 1% burn
             */
            uint256 devTeamAmount = taxFee * 3 / 15;
            uint256 lpRewardAmount = taxFee * 6 / 15;
            uint256 addBackLiquidityAmount = taxFee * 4 / 15;
            uint256 earnAndRewardAmount = taxFee * 1 / 15;
            uint256 burnAmount = taxFee - devTeamAmount - lpRewardAmount - addBackLiquidityAmount - earnAndRewardAmount;
            _transfer(sender, DEV_TEAM_WALLET, devTeamAmount);
            _transfer(sender, LP_REWARD_WALLET, lpRewardAmount);
            _transfer(sender, LP_TO_ADD_BACK_WALLET, addBackLiquidityAmount);
            _transfer(sender, EARN_WALLET, earnAndRewardAmount);
            
            if(burnAmount > 0){
                //burnt the token
                //_burn(sender, burnAmount);
                _transfer(sender, BURN_WALLET, burnAmount);
            }
        }

        // Call local transferFrom
        _transfer(sender, recipient, netAmount);

        return true;

    }
    
}

