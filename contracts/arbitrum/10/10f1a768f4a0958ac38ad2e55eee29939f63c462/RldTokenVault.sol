// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ITokenStrategy.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract RldTokenVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // The strategy currently in use by the vault.
    ITokenStrategy public strategy;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
    }

    function initStrategy(address _strategy) external onlyOwner {
        require(address(strategy) == address(0), "Strategy already set");
        strategy = ITokenStrategy(_strategy);
    }


    function want() public view returns (IERC20) {
        return IERC20(strategy.want());
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
        return want().balanceOf(address(this)) + ITokenStrategy(strategy).balanceOf();
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
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
    function deposit(uint _amount) public nonReentrant {
        strategy.beforeDeposit();
        // The balance of want before transfer
        uint256 _before = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);
        // transfer to strategy and strategy.deposit
        earn();

        // The balance of want after transfer
        uint256 _after = balance();

        // The amount of want that was transferred
        _amount = _after - _before;

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
        want().safeTransfer(address(strategy), _bal);
        strategy.deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public {
        // (vault_want_bal * (withdrawal_amount / total_supply_vault_token)
        // ratio of want in proportion to withdrawal amount
        uint256 userOwedWant = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);
        // how much want is in the vault
        uint vaultWantBal = want().balanceOf(address(this));
        // if the vault has less want than the user is withdrawing,
        // we need to withdraw from the strategy
        if (vaultWantBal < userOwedWant) {
            uint _withdraw = userOwedWant - vaultWantBal;
            strategy.withdraw(_withdraw);
            uint _after = want().balanceOf(address(this));
            uint _diff = _after - vaultWantBal;
            if (_diff < _withdraw) {
                userOwedWant = vaultWantBal + _diff;
            }
        }

        want().safeTransfer(msg.sender, userOwedWant);
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}

