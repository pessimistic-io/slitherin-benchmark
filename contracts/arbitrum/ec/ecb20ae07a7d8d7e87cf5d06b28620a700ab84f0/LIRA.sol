// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// contracts from OpenZeppelin Contracts (last updated v4.8.0)
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./SafeMath.sol";

/**
 * @title Satoshi LIRA Token
 * @author Satoshi LIRA Team
 * @custom:security-contact contact@satoshilira.io
 * @custom:site https://satoshilira.io
 * @custom:whitepaper https://whitepaper.satoshilira.io
 *
 * Unleashing the Power of Decentralization
 *
 * Discover the groundbreaking legacy of Satoshi Nakamoto,
 * the visionary who bestowed upon humanity a cutting-edge digital store of value.
 *
 * Now, it's our time to seize this opportunity and embark on a transformative journey towards a truly decentralized economic system,
 * breaking free from the confines of racial and political restrictions.
 *
 * Join us as we revolutionize the future of finance and empower individuals worldwide.
 * Together, we can shape a brighter and more inclusive tomorrow.
 */
contract LIRA is ERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    uint8 private immutable _decimals = 8;

    IERC20 public immutable wbtc;

    uint private immutable MINT_RATIO = 10000;

    uint public lockedSupply;

    address public feeVault;

    uint8 public burnFee = 5;

    event Mint(address to_, uint input_, uint output_);
    event Burn(address to_, uint input_, uint output_);

    constructor(address wbtc_) ERC20("Satoshi LIRA", "LIRA") {
        wbtc = IERC20(wbtc_);

        feeVault = _msgSender();
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setFeeVault(address feeVault_) public onlyOwner {
        feeVault = feeVault_;
    }

    function setBurnFee(uint8 burnFee_) public onlyOwner {
        require(burnFee_ > 1 && burnFee_ <= 25, "LIRA_INVALID_BURN_FEE");

        burnFee = burnFee_;
    }

    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) private pure returns (uint amountB) {
        require(amountA > 0, "LIRA_QUOTE_INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "LIRA_QUOTE_INSUFFICIENT_LIQUIDITY"
        );

        amountB = amountA.mul(reserveA) / (reserveB);
    }

    function quoteBurnAmounts(uint amount) private view returns (uint, uint) {
        uint fee = amount.div(1000).mul(burnFee);
        return (amount - fee, fee);
    }

    function mint(
        address to,
        uint liraAmount,
        uint wbtcAmount
    ) public onlyOwner {
        require(to != address(this), "LIRA_INVALID_ADDRESS");

        require(
            liraAmount >= MINT_RATIO * 10 ** decimals(),
            "LIRA_INSUFFICIENT_LIRA_AMOUNT"
        );

        require(wbtcAmount >= MINT_RATIO, "LIRA_INSUFFICIENT_WBTC_AMOUNT");

        require(
            lockedSupply + wbtcAmount <= wbtc.balanceOf(address(this)),
            "LIRA_ISSUFFICIENT_WBTC_BALANCE"
        );

        lockedSupply += wbtcAmount;

        _mint(to, liraAmount);

        emit Mint(to, liraAmount, wbtcAmount);
    }

    function quoteMint(
        uint16 blocks,
        uint8 valueBoost
    ) public view returns (uint mintAmount_, uint lockAmount_) {
        require(
            blocks >= 1 && blocks <= MINT_RATIO,
            "LIRA_INVALID_BLOCK_QUANTITY"
        );

        lockAmount_ = MINT_RATIO.mul(blocks);

        require(
            lockedSupply + lockAmount_ <= wbtc.balanceOf(address(this)),
            "LIRA_ISSUFFICIENT_BALANCE"
        );

        uint mintAmount = 0;
        uint supply = totalSupply();

        if (lockedSupply == 0) {
            mintAmount = MINT_RATIO * 10 ** decimals();
        } else {
            require(
                valueBoost > 0 && valueBoost < 100,
                "LIRA_INVALID_VALUE_BOOST"
            );

            for (uint i = 0; i < blocks; i++) {
                mintAmount += quote(
                    MINT_RATIO,
                    supply + mintAmount,
                    lockedSupply + MINT_RATIO.mul(i)
                ).div(100).mul(100 - valueBoost);
            }
        }

        mintAmount_ = mintAmount;
    }

    function burn(address to, uint amount) public {
        require(
            amount >= MINT_RATIO * 10 ** decimals(),
            "LIRA_INSUFFICIENT_AMOUNT"
        );

        (uint liraOutput, uint liraFee) = quoteBurnAmounts(amount);

        uint quoteAmount = quote(liraOutput, lockedSupply, totalSupply());

        (uint wbtcOutput, uint wbtcFee) = quoteBurnAmounts(quoteAmount);

        _burn(_msgSender(), liraOutput);
        transfer(feeVault, liraFee);

        wbtc.safeTransfer(to, wbtcOutput);
        wbtc.safeTransfer(feeVault, wbtcFee);

        lockedSupply -= wbtcOutput;

        emit Burn(to, amount, wbtcOutput);
    }

    function quoteBurn(uint amount) public view returns (uint) {
        (uint liraOutput, ) = quoteBurnAmounts(amount);

        uint quoteAmount = quote(liraOutput, lockedSupply, totalSupply());

        (uint wbtcOutput, ) = quoteBurnAmounts(quoteAmount);

        return wbtcOutput;
    }
}

