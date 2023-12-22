import "./CErc20.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
    
pragma solidity ^0.5.16;

contract Fed {
    using SafeMath for uint;

    CErc20 public ctoken;
    ERC20 public underlying;
    address public chair; // Fed Chair
    address public gov;
    uint public supply;

    event Expansion(uint amount);
    event Contraction(uint amount);

    constructor(CErc20 ctoken_) public {
        ctoken = ctoken_;
        underlying = ERC20(ctoken_.underlying());
        underlying.approve(address(ctoken), uint(-1));
        chair = tx.origin;
        gov = tx.origin;
    }

    function changeGov(address newGov_) public {
        require(msg.sender == gov, "ONLY GOV");
        gov = newGov_;
    }

    function changeChair(address newChair_) public {
        require(msg.sender == gov, "ONLY GOV");
        chair = newChair_;
    }

    function resign() public {
        require(msg.sender == chair, "ONLY CHAIR");
        chair = address(0);
    }

    function expansion(uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        underlying.mint(address(this), amount);
        require(ctoken.mint(amount, false) == 0, 'Supplying failed');
        supply = supply.add(amount);
        emit Expansion(amount);
    }

    function contraction(uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        require(amount <= supply, "AMOUNT TOO BIG"); // can't burn profits
        require(ctoken.redeemUnderlying(amount) == 0, "Redeem failed");
        underlying.burn(amount);
        supply = supply.sub(amount);
        emit Contraction(amount);
    }

    function takeProfit() public {
        uint underlyingBalance = ctoken.balanceOfUnderlying(address(this));
        uint profit = underlyingBalance.sub(supply);
        if(profit > 0) {
            require(ctoken.redeemUnderlying(profit) == 0, "Redeem failed");
            underlying.transfer(gov, profit);
        }
    }
    
}

