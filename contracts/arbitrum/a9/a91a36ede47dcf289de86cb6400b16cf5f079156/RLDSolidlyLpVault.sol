// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ISolidlyLpStrategy.sol";
import "./ISolidlyRouter.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract RLDSolidlyLpVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    ISolidlyLpStrategy public strategy;
    ISolidlyRouter public router;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
    }

    function initStrategy(address _strategy) external onlyOwner {
        require(address(strategy) == address(0), "Strategy already set");
        strategy = ISolidlyLpStrategy(_strategy);
    }

    function want() public view returns (IERC20) {
        return IERC20(strategy.want());
    }

    function inputToken() public view returns (IERC20) {
        return IERC20(strategy.input());
    }
    
    function lpToken0() public view returns (IERC20) {
        return IERC20(strategy.lp0());
    }
    
    function lpToken1() public view returns (IERC20) {
        return IERC20(strategy.lp1());
    }

    function decimals() public view virtual override returns (uint8) {
        address _want = address(strategy.want());
        return ERC20(_want).decimals();
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view returns (uint) {
        return want().balanceOf(address(this)) + ISolidlyLpStrategy(strategy).balanceOf();
    }
    

    /**
    * @dev It returns the total amount of {inputToken} held by the vault.
    */
    function available() public view returns (uint256) {
        return inputToken().balanceOf(address(this));
    }
    
    function availableLpTokens() public view returns(uint256, uint256) {
        return (lpToken0().balanceOf(address(this)), lpToken1().balanceOf(address(this)));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 10 ** decimals() : balance() * 10 ** decimals() / totalSupply();
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(want().balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(uint inputAmount) public nonReentrant {
        strategy.beforeDeposit();
        // The balance of want before transfer
        uint256 _before = balance();
        inputToken().safeTransferFrom(msg.sender, address(this), inputAmount);
        // transfer to strategy and strategy.deposit
        earn();

        // The balance of want after transfer
        uint256 _after = balance();

        // The amount of want that was transferred
        uint256 wantAmount = _after - _before;

        // Additional check for deflationary tokens
        uint256 shares = 0;
        // calculate LP tokens to mint for depositor
        if (totalSupply() == 0) {
            shares = wantAmount;
        } else {
            shares = (wantAmount * totalSupply()) / _before;
        }
        _mint(msg.sender, shares);
    }

    function depositLpTokens(uint256 amount0, uint256 amount1) public nonReentrant {
        strategy.beforeDeposit();
        // The balance of want before transfer
        uint256 _before = balance();
        
        lpToken0().safeTransferFrom(msg.sender, address(this), amount0);
        lpToken1().safeTransferFrom(msg.sender, address(this), amount1);
        // transfer to strategy and strategy.deposit
        earnLpTokens();

        // The balance of want after transfer
        uint256 _after = balance();

        // The amount of want that was transferred
        uint256 _amount = _after - _before;

        // Additional check for deflationary tokens
        uint256 shares = 0;
        // calculate LP tokens to mint for depositor
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / _before;
        }
        _mint(msg.sender, shares);
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn() public {
        uint _bal = available();
        inputToken().safeTransfer(address(strategy), _bal);
        strategy.deposit();
    }
    
    function earnLpTokens() public {
        (uint256 _bal0, uint256 _bal1) = availableLpTokens();
        lpToken0().safeTransfer(address(strategy), _bal0);
        lpToken1().safeTransfer(address(strategy), _bal1);
        strategy.depositLpTokens();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        _withdraw(balanceOf(msg.sender), true);
    }
    
    function withdrawAllAsLpTokens() external {
        _withdraw(balanceOf(msg.sender), false);
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function _withdraw(uint256 _shares, bool asInputToken) public virtual {
        uint256 userOwedWant = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);
        if (asInputToken) {
            strategy.withdraw(userOwedWant);
            uint inputTokenBal = inputToken().balanceOf(address(this));
            inputToken().safeTransfer(msg.sender, inputTokenBal);
        } else {
            strategy.withdrawAsLpTokens(userOwedWant);
            uint256 lpToken0Bal = lpToken0().balanceOf(address(this));
            uint256 lpToken1Bal = lpToken1().balanceOf(address(this));
            lpToken0().safeTransfer(msg.sender, lpToken0Bal);
            lpToken1().safeTransfer(msg.sender, lpToken1Bal);
        }
    }
    
    function withdraw(uint256 _shares) public virtual {
        _withdraw(_shares, true);
    }
    
    function withdrawAsLpTokens(uint256 _shares) public virtual {
        _withdraw(_shares, false);
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(inputToken()), "!token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}

