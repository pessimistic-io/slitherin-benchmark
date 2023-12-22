// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./ERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./PRBMathUD60x18.sol";

/**
  @title Promify Celebrity token contract with integrated swapping economic system.
  Economist Dmitry Vizhnitsky
  @author Gosha Skryuchenkov @ Prometeus Labs

  This contract is used when deploying Celebrity Token.
  Celeberity Token has 10 decimals.
  Economic system for token price ratio growth is designed specifically for this contract.
  Economic system is described at https://promify.io/whitepaper
  
  Contract is written due to high complexity of calculations they had be done in binary form. 
  PRBMath library is used as a tool that allows binary calculations.
*/

contract PromifyArbitrum is ERC20Upgradeable {
    uint256 public starSupply;
    uint256 public starRetrieved;
    uint256 public supplySold;
    uint256 public starShare;
    uint256 public promIn;
    uint256 public highestSoldPoint;
    uint256 public scaleFactor = 10**8;
    uint256 public reserve = 100000000000000000;
    uint256 public curve3S0;
    uint256 public accessTimes;
    bool public curveState;
    address public PROM;
    address public starAddress;
    address public DAO;

    mapping(address => uint256) public soldInDay;
    mapping(address => uint256) public soldLastTime;

    event BuyEvent(address caller, address reciever, uint256 amount);
    event SellEvent(
        address caller,
        address supporter,
        address reciever,
        uint256 amountCC,
        uint256 amountPROM
    );
    event LatestPrice(uint256 amount);
    event StarAirdrop(uint256 amount);
    event CoinCreation(
        string name,
        string symbol,
        address addressPROM,
        uint256 starAllo,
        address celebrityAddress
    );

    /**
     @param name The name of the new CC token.
     @param symbol The symbol of the new CC token.
     @param addressPROM The Address of PROM token, used for swapping CC tokens.
     @param starAllo The percentage of CC token total supply that Celebrity allocated to oneself.
     @param celebrityAddress The address that Celebrity Supply is linked to.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address addressPROM,
        uint256 starAllo,
        address celebrityAddress,
        address _DAO
    ) external initializer {
        require(starAllo <= 20, "Celebrity percentage is too big");
        __ERC20_init(name, symbol);
        uint256 supply = 100000 * (10**10);
        _mint(address(this), supply);
        starShare = starAllo;
        starSupply = (supply * starShare) / 100;
        PROM = addressPROM;
        starAddress = celebrityAddress;
        DAO = _DAO;
        emit CoinCreation(
            name,
            symbol,
            addressPROM,
            starAllo,
            celebrityAddress
        );
    }

    function updateVariables() public {
        require(accessTimes == 0, "Accessed already");
        scaleFactor = 10**8;
        reserve = 100000000000000000;
        accessTimes = 1;
    }

    function decimals() public pure override returns (uint8) {
        return 10;
    }

    /**
     @param supporter The address that sells CC token and receives PROM token
     @param amount The amount of CC token that is getting sold
     @param reciever The reciever of PROM token
     @param slippageAmount The very least amount of PROM tokens user expects to get after sale. 18 decimals
     
     This method allows to swap CC token to receive PROM using designated economic system
     This method checks user's 22150 blocks cap which is floating and calculated at the time transaction is mined
     This method chooses which curve should be used for calculations at the time transaction is mined
     This method transfers PROM from contract instance and transfers CC token to contract instance from "supporter"
     
     More information about selling curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function sellCC(
        address supporter,
        address reciever,
        uint256 amount,
        uint256 slippageAmount
    ) external {
        if (msg.sender != supporter) {
            require(msg.sender == DAO, "Access Denied");
        }
        uint256 amt;
        uint256 latestPrice;
        uint256 stateCheck;
        if (curveState) {
            amt = VSpecial(amount);
        } else if (supplySold < amount) {
            stateCheck = VSpecial2(amount);
            amt = stateCheck + promIn;
            curve3S0 = starSupply - (amount - supplySold);
        } else if (
            supplySold - amount >
            (((totalSupply() * (100 - starShare)) / 100) * 2) / 10 &&
            curveState == false
        ) {
            amt = V2(amount);
        } else if (
            supplySold <=
            (((totalSupply() * (100 - starShare)) / 100) * 2) / 10 &&
            curveState == false
        ) {
            amt = V1(amount);
        } else if (curveState == false) {
            amt = V3(amount);
            amt =
                promIn +
                amt -
                ((7136248173270400000000 * (100 - starShare)) / 100);
        }
        if (supporter != starAddress) {
            if (block.number - 22150 < soldLastTime[supporter]) {
                require(amt + soldInDay[supporter] <= cap(), "Cap");
                soldInDay[supporter] = soldInDay[supporter] + amt;
            } else {
                soldLastTime[supporter] = block.number;
                soldInDay[supporter] = amt;
            }
        }
        if (supplySold <= amount) {
            supplySold = 0;
        } else {
            supplySold = supplySold - amount;
        }
        if (promIn <= amt) {
            promIn = 0;
        } else {
            promIn = promIn - amt;
        }
        latestPrice = amt / amount;
        if (stateCheck != 0) {
            curveState = true;
            reserve = reserve - stateCheck;
        }
        require(amt >= slippageAmount, "Slippage too high");
        IERC20Upgradeable(address(this)).transferFrom(
            supporter,
            address(this),
            amount
        );
        IERC20Upgradeable(PROM).transfer(reciever, amt);
        emit SellEvent(msg.sender, supporter, reciever, amount, amt);
        emit LatestPrice(latestPrice);
    }

    /**
     @param supporter The address that sends PROM token and recieves CC token
     @param amount The amount of PROM token that is getting sent
     @param slippageAmount The very least amount of CC user expects to see after trade. 10 decimals
     
     This method allows to swap PROM token to recieve CC token using designated economic system
     This method chooses which curve should be used for calculations at the time transaction is mined
     This method transfers CC from contract instance and transfers PROM token to contract instance from transaction caller
     
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */

    function buyCC(
        uint256 amount,
        address supporter,
        uint256 slippageAmount
    ) external {
        uint256 amt;
        if (
            promIn + amount <= 71362481732704000000 * (100 - starShare) &&
            curveState == false
        ) {
            amt = S1(amount) - supplySold;
        } else if (
            supplySold > ((totalSupply() - starSupply) * 2) / 10 &&
            curveState == false
        ) {
            amt = S2(amount) - supplySold;
        } else if (curveState == false) {
            amt = S3(amount) - supplySold;
        }
        if (curveState) {
            if (amount + reserve <= 100000000000000000) {
                curve3S0 = SSpecial(amount);
                amt = curve3S0 - supplySold;
            } else if (
                promIn + amount <= 71362481732704000000 * (100 - starShare)
            ) {
                amt = S1(amount) + starSupply - curve3S0;
                curveState = false;
                reserve = 100000000000000000;
            } else {
                amt = S3(amount) + starSupply - curve3S0;
                curveState = false;
                reserve = 100000000000000000;
            }
        }
        require(amt >= slippageAmount, "Slippage too high");
        require(totalSupply() - supplySold - amt >= starSupply, "Curve 0");
        uint256 latestPrice = amount / amt;
        supplySold = supplySold + amt;
        promIn = promIn + amount;
        if (highestSoldPoint < supplySold) {
            highestSoldPoint = supplySold;
        }
        IERC20Upgradeable(PROM).transferFrom(msg.sender, address(this), amount);
        IERC20Upgradeable(address(this)).transfer(supporter, amt);
        emit BuyEvent(msg.sender, supporter, amount);
        emit LatestPrice(latestPrice);
    }

    /**
    This method allows to send 10% of Celebrity Supply to "starAddress"
    This method can be called once for every 4% of Total supply(excluding star Supply) that's bought out of the Curve up to 40%.
     */
    function transferToStar() external {
        uint256 amount = starSupply / 10;
        require(starRetrieved + amount <= starSupply, "Retrieved all");
        uint256 eligbleParts = (highestSoldPoint * 100) /
            (totalSupply() - starSupply) /
            4;
        uint256 eligbleTime = 0;
        for (uint256 i = 0; i < eligbleParts && i < 10; ++i) {
            eligbleTime = eligbleTime + 1;
        }
        require(
            starRetrieved + amount <= (eligbleTime * starSupply) / 10,
            "Not yet"
        );
        starRetrieved = starRetrieved + amount;
        IERC20Upgradeable(address(this)).transfer(starAddress, amount);
        emit StarAirdrop(amount);
    }

    /**
     @param amount The amount of CC token that is getting sold
     
     Internal method that calculates selling price for Curve 1
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper 
     */
    function V1(uint256 amount) public view returns (uint256 result) {
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _amount = PRBMathUD60x18.fromUint(amount);
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.fromUint(supplySold);
        PRBMath.UD60x18 memory _S1 = PRBMathUD60x18.sub(_S0, _amount);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        _S1 = PRBMathUD60x18.mul(_S1, PRBMathUD60x18.fromUint(scaleFactor));

        PRBMath.UD60x18 memory lnNumerator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerNum = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S0
        );
        powerNum = PRBMathUD60x18.div(powerNum, PRBMathUD60x18.fromUint(10));
        powerNum = PRBMathUD60x18.div(powerNum, _a);
        if (PRBMathUD60x18.toUint(powerNum) >= 4) {
            powerNum = PRBMathUD60x18.sub(powerNum, PRBMathUD60x18.fromUint(4));
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
        } else {
            powerNum = PRBMathUD60x18.sub(PRBMathUD60x18.fromUint(4), powerNum);
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
            lnNumerator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnNumerator
            );
        }
        lnNumerator = PRBMathUD60x18.add(
            lnNumerator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory lnDenominator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerDen = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S1
        );
        powerDen = PRBMathUD60x18.div(powerDen, PRBMathUD60x18.fromUint(10));
        powerDen = PRBMathUD60x18.div(powerDen, _a);
        if (PRBMathUD60x18.toUint(powerDen) >= 4) {
            powerDen = PRBMathUD60x18.sub(powerDen, PRBMathUD60x18.fromUint(4));
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
        } else {
            powerDen = PRBMathUD60x18.sub(PRBMathUD60x18.fromUint(4), powerDen);
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
            lnDenominator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnDenominator
            );
        }
        lnDenominator = PRBMathUD60x18.add(
            lnDenominator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.div(
            lnNumerator,
            lnDenominator
        );
        _result = PRBMathUD60x18.ln(_result);
        _result = PRBMathUD60x18.mul(_result, _a);
        _result = PRBMathUD60x18.mul(_result, PRBMathUD60x18.fromUint(125));
        _result = PRBMathUD60x18.div(_result, PRBMathUD60x18.fromUint(330));
        result = PRBMathUD60x18.toUint(_result);
        return result;
    }

    /**
     @param amount The amount of CC token that is getting sold
     
     Internal method that calculates selling price for Curve 2
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function V2(uint256 amount) public view returns (uint256 result) {
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _amount = PRBMathUD60x18.fromUint(amount);
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.fromUint(supplySold);
        PRBMath.UD60x18 memory _S1 = PRBMathUD60x18.sub(_S0, _amount);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        _S1 = PRBMathUD60x18.mul(_S1, PRBMathUD60x18.fromUint(scaleFactor));

        PRBMath.UD60x18 memory lnNumerator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerNum = PRBMathUD60x18.div(_S0, _a);

        if (PRBMathUD60x18.toUint(powerNum) >= 3) {
            powerNum = PRBMathUD60x18.sub(powerNum, PRBMathUD60x18.fromUint(3));
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
        } else {
            powerNum = PRBMathUD60x18.sub(PRBMathUD60x18.fromUint(3), powerNum);
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
            lnNumerator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnNumerator
            );
        }
        lnNumerator = PRBMathUD60x18.add(
            lnNumerator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory lnDenominator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerDen = PRBMathUD60x18.div(_S1, _a);
        if (PRBMathUD60x18.toUint(powerDen) >= 3) {
            powerDen = PRBMathUD60x18.sub(powerDen, PRBMathUD60x18.fromUint(3));
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
        } else {
            powerDen = PRBMathUD60x18.sub(PRBMathUD60x18.fromUint(3), powerDen);
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
            lnDenominator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnDenominator
            );
        }
        lnDenominator = PRBMathUD60x18.add(
            lnDenominator,
            PRBMathUD60x18.fromUint(1)
        );
        PRBMath.UD60x18 memory _result = PRBMathUD60x18.div(
            lnNumerator,
            lnDenominator
        );
        _result = PRBMathUD60x18.ln(_result);
        _result = PRBMathUD60x18.mul(_result, PRBMathUD60x18.fromUint(5));
        _result = PRBMathUD60x18.mul(_result, _a);

        result = PRBMathUD60x18.toUint(_result);
        return result;
    }

    /**
     @param amount The amount of PROM token that is getting sent in order to obtain CC token
     
     Internal method that calculates buing price for Curve 1
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function S1(uint256 amount) public view returns (uint256 result) {
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.fromUint(supplySold);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(125));
        _S0 = PRBMathUD60x18.div(_S0, PRBMathUD60x18.fromUint(100));
        PRBMath.UD60x18 memory _V = PRBMathUD60x18.fromUint(amount);

        PRBMath.UD60x18 memory powerFactor1 = PRBMathUD60x18.add(_V, _S0);
        powerFactor1 = PRBMathUD60x18.mul(
            powerFactor1,
            PRBMathUD60x18.fromUint(264)
        );
        powerFactor1 = PRBMathUD60x18.div(
            powerFactor1,
            PRBMathUD60x18.fromUint(100)
        );
        powerFactor1 = PRBMathUD60x18.div(powerFactor1, _a);
        PRBMath.UD60x18 memory lnInput1 = PRBMathUD60x18.e();
        if (PRBMathUD60x18.toUint(powerFactor1) >= 4) {
            powerFactor1 = PRBMathUD60x18.sub(
                powerFactor1,
                PRBMathUD60x18.fromUint(4)
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
        } else {
            powerFactor1 = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(4),
                powerFactor1
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
            lnInput1 = PRBMathUD60x18.div(PRBMathUD60x18.fromUint(1), lnInput1);
        }

        PRBMath.UD60x18 memory lnInput2 = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerFactor2 = PRBMathUD60x18.mul(
            _V,
            PRBMathUD60x18.fromUint(264)
        );
        powerFactor2 = PRBMathUD60x18.div(
            powerFactor2,
            PRBMathUD60x18.fromUint(100)
        );
        powerFactor2 = PRBMathUD60x18.div(powerFactor2, _a);
        lnInput2 = PRBMathUD60x18.pow(lnInput2, powerFactor2);
        lnInput2 = PRBMathUD60x18.add(lnInput2, lnInput1);
        lnInput2 = PRBMathUD60x18.sub(lnInput2, PRBMathUD60x18.fromUint(1));
        PRBMath.UD60x18 memory poweredE = PRBMathUD60x18.e();
        poweredE = PRBMathUD60x18.pow(poweredE, PRBMathUD60x18.fromUint(4));
        lnInput2 = PRBMathUD60x18.mul(lnInput2, poweredE);

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.ln(lnInput2);
        _result = PRBMathUD60x18.mul(_result, PRBMathUD60x18.fromUint(10));
        _result = PRBMathUD60x18.div(_result, PRBMathUD60x18.fromUint(33));
        _result = PRBMathUD60x18.mul(_result, _a);
        result = PRBMathUD60x18.toUint(_result);
        result = result / scaleFactor;

        return result;
    }

    /**
     @param amount The amount of PROM token that is getting sent in order to obtain CC token
     
     Internal method that calculates buing price for Curve 2
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function S2(uint256 amount) public view returns (uint256 result) {
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.fromUint(supplySold);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _V = PRBMathUD60x18.fromUint(amount);

        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(5));
        PRBMath.UD60x18 memory powerFactor1 = PRBMathUD60x18.add(_V, _S0);
        powerFactor1 = PRBMathUD60x18.mul(
            powerFactor1,
            PRBMathUD60x18.fromUint(2)
        );
        powerFactor1 = PRBMathUD60x18.div(powerFactor1, _a);
        powerFactor1 = PRBMathUD60x18.div(
            powerFactor1,
            PRBMathUD60x18.fromUint(10)
        );
        PRBMath.UD60x18 memory lnInput1 = PRBMathUD60x18.e();
        if ((PRBMathUD60x18.toUint(powerFactor1) >= 3)) {
            powerFactor1 = PRBMathUD60x18.sub(
                powerFactor1,
                PRBMathUD60x18.fromUint(3)
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
        } else {
            powerFactor1 = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(3),
                powerFactor1
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
            lnInput1 = PRBMathUD60x18.div(PRBMathUD60x18.fromUint(1), lnInput1);
        }

        PRBMath.UD60x18 memory lnInput2 = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerFactor2 = PRBMathUD60x18.mul(
            _V,
            PRBMathUD60x18.fromUint(2)
        );
        powerFactor2 = PRBMathUD60x18.div(powerFactor2, _a);
        powerFactor2 = PRBMathUD60x18.div(
            powerFactor2,
            PRBMathUD60x18.fromUint(10)
        );
        lnInput2 = PRBMathUD60x18.pow(lnInput2, powerFactor2);
        lnInput2 = PRBMathUD60x18.add(lnInput2, lnInput1);
        lnInput2 = PRBMathUD60x18.sub(lnInput2, PRBMathUD60x18.fromUint(1));
        PRBMath.UD60x18 memory poweredE = PRBMathUD60x18.e();
        poweredE = PRBMathUD60x18.pow(poweredE, PRBMathUD60x18.fromUint(3));
        lnInput2 = PRBMathUD60x18.mul(lnInput2, poweredE);

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.ln(lnInput2);
        _result = PRBMathUD60x18.mul(_result, _a);
        _result = PRBMathUD60x18.div(
            _result,
            PRBMathUD60x18.fromUint(scaleFactor)
        );
        result = PRBMathUD60x18.toUint(_result);

        return result;
    }

    /**
     @param amount The amount of PROM token that is getting sent in order to obtain CC token
     
     Internal method that calculates buing price for transition of Curve 1 -> Curve 2
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function S3(uint256 amount) public view returns (uint256 result) {
        uint256 customSupply = (totalSupply() * (100 - starShare) * 2) / 1000;
        uint256 customAmount = amount -
            ((7136248173270400000000 * (100 - starShare)) / 100 - promIn);
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.fromUint(customSupply);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _V = PRBMathUD60x18.fromUint(customAmount);

        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(5));
        PRBMath.UD60x18 memory powerFactor1 = PRBMathUD60x18.add(_V, _S0);
        powerFactor1 = PRBMathUD60x18.mul(
            powerFactor1,
            PRBMathUD60x18.fromUint(2)
        );
        powerFactor1 = PRBMathUD60x18.div(powerFactor1, _a);
        powerFactor1 = PRBMathUD60x18.div(
            powerFactor1,
            PRBMathUD60x18.fromUint(10)
        );
        PRBMath.UD60x18 memory lnInput1 = PRBMathUD60x18.e();
        if ((PRBMathUD60x18.toUint(powerFactor1) >= 3)) {
            powerFactor1 = PRBMathUD60x18.sub(
                powerFactor1,
                PRBMathUD60x18.fromUint(3)
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
        } else {
            powerFactor1 = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(3),
                powerFactor1
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
            lnInput1 = PRBMathUD60x18.div(PRBMathUD60x18.fromUint(1), lnInput1);
        }

        PRBMath.UD60x18 memory lnInput2 = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerFactor2 = PRBMathUD60x18.mul(
            _V,
            PRBMathUD60x18.fromUint(2)
        );
        powerFactor2 = PRBMathUD60x18.div(powerFactor2, _a);
        powerFactor2 = PRBMathUD60x18.div(
            powerFactor2,
            PRBMathUD60x18.fromUint(10)
        );
        lnInput2 = PRBMathUD60x18.pow(lnInput2, powerFactor2);
        lnInput2 = PRBMathUD60x18.add(lnInput2, lnInput1);
        lnInput2 = PRBMathUD60x18.sub(lnInput2, PRBMathUD60x18.fromUint(1));
        PRBMath.UD60x18 memory poweredE = PRBMathUD60x18.e();
        poweredE = PRBMathUD60x18.pow(poweredE, PRBMathUD60x18.fromUint(3));
        lnInput2 = PRBMathUD60x18.mul(lnInput2, poweredE);

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.ln(lnInput2);
        _result = PRBMathUD60x18.mul(_result, _a);
        _result = PRBMathUD60x18.div(
            _result,
            PRBMathUD60x18.fromUint(scaleFactor)
        );
        result = PRBMathUD60x18.toUint(_result);

        return result;
    }

    /**
     @param amount The amount of CC token that is getting sold
     
     Internal method that calculates selling price for transition of Curve 1 -> Curve 2
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function V3(uint256 amount) public view returns (uint256 result) {
        uint256 customS1 = (totalSupply() * (100 - starShare) * 2) / 1000;
        uint256 customSupplySold = supplySold - amount;
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.fromUint(customSupplySold);
        PRBMath.UD60x18 memory _S1 = PRBMathUD60x18.fromUint(customS1);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        _S1 = PRBMathUD60x18.mul(_S1, PRBMathUD60x18.fromUint(scaleFactor));

        PRBMath.UD60x18 memory lnNumerator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerNum = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S1
        );
        powerNum = PRBMathUD60x18.div(powerNum, PRBMathUD60x18.fromUint(10));
        powerNum = PRBMathUD60x18.div(powerNum, _a);
        if (PRBMathUD60x18.toUint(powerNum) >= 4) {
            powerNum = PRBMathUD60x18.sub(powerNum, PRBMathUD60x18.fromUint(4));
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
        } else {
            powerNum = PRBMathUD60x18.sub(PRBMathUD60x18.fromUint(4), powerNum);
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
            lnNumerator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnNumerator
            );
        }
        lnNumerator = PRBMathUD60x18.add(
            lnNumerator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory lnDenominator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerDen = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S0
        );
        powerDen = PRBMathUD60x18.div(powerDen, PRBMathUD60x18.fromUint(10));
        powerDen = PRBMathUD60x18.div(powerDen, _a);
        if (PRBMathUD60x18.toUint(powerDen) >= 4) {
            powerDen = PRBMathUD60x18.sub(powerDen, PRBMathUD60x18.fromUint(4));
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
        } else {
            powerDen = PRBMathUD60x18.sub(PRBMathUD60x18.fromUint(4), powerDen);
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
            lnDenominator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnDenominator
            );
        }
        lnDenominator = PRBMathUD60x18.add(
            lnDenominator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.div(
            lnNumerator,
            lnDenominator
        );
        _result = PRBMathUD60x18.ln(_result);
        _result = PRBMathUD60x18.mul(_result, _a);
        _result = PRBMathUD60x18.mul(_result, PRBMathUD60x18.fromUint(125));
        _result = PRBMathUD60x18.div(_result, PRBMathUD60x18.fromUint(330));
        result = PRBMathUD60x18.toUint(_result);
        return result;
    }

    /**
     @param amount The amount of CC token that is getting sold 
     
     Internal method that calculates selling price for a special case #1
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function VSpecial(uint256 amount) public view returns (uint256 result) {
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _amount = PRBMathUD60x18.fromUint(amount);
        PRBMath.UD60x18 memory _S1 = PRBMathUD60x18.fromUint(starSupply);
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.sub(_S1, _amount);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        _S1 = PRBMathUD60x18.mul(_S1, PRBMathUD60x18.fromUint(scaleFactor));

        PRBMath.UD60x18 memory lnNumerator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerNum = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S1
        );
        powerNum = PRBMathUD60x18.div(powerNum, PRBMathUD60x18.fromUint(10));
        powerNum = PRBMathUD60x18.div(powerNum, _a);
        if (PRBMathUD60x18.toUint(powerNum) >= 14) {
            powerNum = PRBMathUD60x18.sub(
                powerNum,
                PRBMathUD60x18.fromUint(14)
            );
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
        } else {
            powerNum = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(14),
                powerNum
            );
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
            lnNumerator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnNumerator
            );
        }
        lnNumerator = PRBMathUD60x18.add(
            lnNumerator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory lnDenominator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerDen = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S0
        );
        powerDen = PRBMathUD60x18.div(powerDen, PRBMathUD60x18.fromUint(10));
        powerDen = PRBMathUD60x18.div(powerDen, _a);
        if (PRBMathUD60x18.toUint(powerDen) >= 14) {
            powerDen = PRBMathUD60x18.sub(
                powerDen,
                PRBMathUD60x18.fromUint(14)
            );
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
        } else {
            powerDen = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(14),
                powerDen
            );
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
            lnDenominator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnDenominator
            );
        }
        lnDenominator = PRBMathUD60x18.add(
            lnDenominator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.div(
            lnNumerator,
            lnDenominator
        );
        _result = PRBMathUD60x18.ln(_result);
        _result = PRBMathUD60x18.mul(_result, _a);
        _result = PRBMathUD60x18.mul(_result, PRBMathUD60x18.fromUint(125));
        _result = PRBMathUD60x18.div(_result, PRBMathUD60x18.fromUint(330));
        result = PRBMathUD60x18.toUint(_result);
        return result;
    }

    /**
     @param amount The amount of CC token that is getting sold in order to obtain CC token
     
     Internal method that calculates selling price for a special case #2
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function VSpecial2(uint256 amount) public view returns (uint256 result) {
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _amount = PRBMathUD60x18.fromUint(amount);
        PRBMath.UD60x18 memory _S1 = PRBMathUD60x18.fromUint(starSupply);
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.sub(
            _amount,
            PRBMathUD60x18.fromUint(supplySold)
        );
        _S0 = PRBMathUD60x18.sub(_S1, _S0);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        _S1 = PRBMathUD60x18.mul(_S1, PRBMathUD60x18.fromUint(scaleFactor));

        PRBMath.UD60x18 memory lnNumerator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerNum = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S1
        );
        powerNum = PRBMathUD60x18.div(powerNum, PRBMathUD60x18.fromUint(10));
        powerNum = PRBMathUD60x18.div(powerNum, _a);
        if (PRBMathUD60x18.toUint(powerNum) >= 14) {
            powerNum = PRBMathUD60x18.sub(
                powerNum,
                PRBMathUD60x18.fromUint(14)
            );
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
        } else {
            powerNum = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(14),
                powerNum
            );
            lnNumerator = PRBMathUD60x18.pow(lnNumerator, powerNum);
            lnNumerator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnNumerator
            );
        }
        lnNumerator = PRBMathUD60x18.add(
            lnNumerator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory lnDenominator = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerDen = PRBMathUD60x18.mul(
            PRBMathUD60x18.fromUint(33),
            _S0
        );
        powerDen = PRBMathUD60x18.div(powerDen, PRBMathUD60x18.fromUint(10));
        powerDen = PRBMathUD60x18.div(powerDen, _a);
        if (PRBMathUD60x18.toUint(powerDen) >= 14) {
            powerDen = PRBMathUD60x18.sub(
                powerDen,
                PRBMathUD60x18.fromUint(14)
            );
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
        } else {
            powerDen = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(14),
                powerDen
            );
            lnDenominator = PRBMathUD60x18.pow(lnDenominator, powerDen);
            lnDenominator = PRBMathUD60x18.div(
                PRBMathUD60x18.fromUint(1),
                lnDenominator
            );
        }
        lnDenominator = PRBMathUD60x18.add(
            lnDenominator,
            PRBMathUD60x18.fromUint(1)
        );

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.div(
            lnNumerator,
            lnDenominator
        );
        _result = PRBMathUD60x18.ln(_result);
        _result = PRBMathUD60x18.mul(_result, _a);
        _result = PRBMathUD60x18.mul(_result, PRBMathUD60x18.fromUint(125));
        _result = PRBMathUD60x18.div(_result, PRBMathUD60x18.fromUint(330));
        result = PRBMathUD60x18.toUint(_result);
        return result;
    }

    /**
     @param amount The amount of PROM token that is getting sold in order to obtain CC token
     
     Internal method that calculates buying price for a special case #1
     More information about buying curves and economic system may be found at:
     https://promify.io/whitepaper
     */
    function SSpecial(uint256 amount) public view returns (uint256 result) {
        PRBMath.UD60x18 memory _a = PRBMathUD60x18.fromUint(a());
        _a = PRBMathUD60x18.mul(_a, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _S0 = PRBMathUD60x18.fromUint(curve3S0);
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(scaleFactor));
        PRBMath.UD60x18 memory _V = PRBMathUD60x18.fromUint(amount);
        _V = PRBMathUD60x18.sub(_V, PRBMathUD60x18.fromUint(promIn));
        _S0 = PRBMathUD60x18.mul(_S0, PRBMathUD60x18.fromUint(125));
        _S0 = PRBMathUD60x18.div(_S0, PRBMathUD60x18.fromUint(100));

        PRBMath.UD60x18 memory powerFactor1 = PRBMathUD60x18.add(_V, _S0);
        powerFactor1 = PRBMathUD60x18.mul(
            powerFactor1,
            PRBMathUD60x18.fromUint(264)
        );
        powerFactor1 = PRBMathUD60x18.div(
            powerFactor1,
            PRBMathUD60x18.fromUint(100)
        );
        powerFactor1 = PRBMathUD60x18.div(powerFactor1, _a);
        PRBMath.UD60x18 memory lnInput1 = PRBMathUD60x18.e();
        if (PRBMathUD60x18.toUint(powerFactor1) >= 14) {
            powerFactor1 = PRBMathUD60x18.sub(
                powerFactor1,
                PRBMathUD60x18.fromUint(14)
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
        } else {
            powerFactor1 = PRBMathUD60x18.sub(
                PRBMathUD60x18.fromUint(14),
                powerFactor1
            );
            lnInput1 = PRBMathUD60x18.pow(lnInput1, powerFactor1);
            lnInput1 = PRBMathUD60x18.div(PRBMathUD60x18.fromUint(1), lnInput1);
        }

        PRBMath.UD60x18 memory lnInput2 = PRBMathUD60x18.e();
        PRBMath.UD60x18 memory powerFactor2 = PRBMathUD60x18.mul(
            _V,
            PRBMathUD60x18.fromUint(264)
        );
        powerFactor2 = PRBMathUD60x18.div(
            powerFactor2,
            PRBMathUD60x18.fromUint(100)
        );
        powerFactor2 = PRBMathUD60x18.div(powerFactor2, _a);
        lnInput2 = PRBMathUD60x18.pow(lnInput2, powerFactor2);
        lnInput2 = PRBMathUD60x18.add(lnInput2, lnInput1);
        lnInput2 = PRBMathUD60x18.sub(lnInput2, PRBMathUD60x18.fromUint(1));
        PRBMath.UD60x18 memory poweredE = PRBMathUD60x18.e();
        poweredE = PRBMathUD60x18.pow(poweredE, PRBMathUD60x18.fromUint(14));
        lnInput2 = PRBMathUD60x18.mul(lnInput2, poweredE);

        PRBMath.UD60x18 memory _result = PRBMathUD60x18.ln(lnInput2);
        _result = PRBMathUD60x18.mul(_result, PRBMathUD60x18.fromUint(10));
        _result = PRBMathUD60x18.div(_result, PRBMathUD60x18.fromUint(33));
        _result = PRBMathUD60x18.mul(_result, _a);
        result = PRBMathUD60x18.toUint(_result);
        result = result / scaleFactor;

        return result;
    }

    function a() public view returns (uint256 _a) {
        _a = ((12500 * (10**10) * (100 - starShare)) / 100);
        return _a;
    }

    function cap() public view returns (uint256 result) {
        result =
            (promIn * 162 * supplySold) /
            (17010 * (supplySold + starSupply));
        if (result >= 5 * (10**18)) {
            return result;
        } else {
            result = 5 * (10**18);
            return result;
        }
    }

    function updateDAO(address newDAO) public {
        require(msg.sender == DAO, "Access denied");
        DAO = newDAO;
    }
}

