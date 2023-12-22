//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./IDXBL.sol";
import "./console.sol";

/**
 * The DXBL Token. It uses a minter role to control who can mint and burn tokens. That is 
 * set to the RevshareVault contract so that it completely controls the supply of DXBL.
 */
contract DXBL is ERC20, IDXBL {

    //minter allowed to mint/burn. This should be revshare contract
    address public minter;
    
    //discount bps per DXBL owned 5 = .05%
    uint32 public discountPerTokenBps;

    //restrict function to only minter address
    modifier onlyMinter() {
        require(msg.sender == minter, "Unauthorized");
        _;
    }

    event DiscountRateChanged(uint32 newRate);

    //minter is revshare vault
    constructor(address _minter, 
                uint32 discountRate,
                string memory name, 
                string memory symbol) ERC20(name, symbol) {
        require(_minter != address(0), "Invalid minter");
        uint32 size;
        assembly {
            size := extcodesize(_minter)
        }
        require (size > 0, "Minter must be a contract");

        minter = _minter;
        discountPerTokenBps = discountRate;
    }

    //time-locked change from revshare vault configuration
    function setDiscountRate(uint32 discount) external override onlyMinter {
        discountPerTokenBps = discount;
        emit DiscountRateChanged(discount);
    }

    /**
     * Compute how much of a discount to give for a trade based on how many
     * DXBL tokens the trader owns. Apply a min fee if total is less than 
     * min required.
     */
    function computeDiscountedFee(FeeRequest calldata request) external view override returns(uint) {

        //compute the standard rate fee
        uint fee = ((request.amt * request.stdBpsRate) / 10000);
        if(request.referred) {
            //apply 10% discount if referred by affiliate
            fee = (fee * 10) / 100;
        }
        
       //get the trader's DXBL token balance
        uint bal = request.dxblBalance;
        if(bal == 0) {
            return fee;
        }
        
        //determine what their discount is based on their balance
        uint discRate = (bal * discountPerTokenBps)/10000;
        
        //and the min fee required
        uint minFee = ((request.amt * request.minBpsRate) / 10000);
        
        uint disc = (fee * discRate) / 1e18;
        if(disc > fee) {
            return minFee;
        }

        //apply the discount percentage but divide out DXBL token decimals
        fee -= disc;
        if(fee < minFee) {
            fee = minFee;
        }
        return fee;
    }

    /**
     * Mint new tokens for a trader. Only callable by the assigned minter contract
     */
    function mint(address receiver, uint amount) public override onlyMinter {
        _mint(receiver, amount);
    }

    /**
     * Burn tokens from a trader. Only callable by the assigned minter contract
     */
    function burn(address burner, uint amount) public override onlyMinter {
        _burn(burner, amount);
    }

    /**
        NO OP
     */
    function _beforeTokenTransfer(address from, address to, uint amount) internal override  {

    }

    /**
        NO OP
     */
    function _afterTokenTransfer(address from, address to, uint amount) internal override  {

    }
}
