// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./console.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";

import "./MiniController.sol";

contract Vault is ERC20, MiniController {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public min = 9500;
    uint256 public constant MAX = 10000;

    constructor(address _token, address _sushiswap) ERC20("Wrapped MIM-2CRV", "wMIM-2CRV") MiniController(_token, _sushiswap) {}

    // The minimum amount that can be used by the strategy
    function setMin(uint256 _min) external {
        require(msg.sender == governance, "!governance");
        min = _min;
    }

    // Balance of want token is the Vault balance + Strategy balance + strategy sorb balance
    function balance() public view returns (uint256) {
        return token.balanceOf(address(this)).add(token.balanceOf(strategy));
    }

    // Balance of want token is the Vault balance + Strategy balance + strategy sorb balance
    function totalAssets() public view returns (uint256) {
        return token.balanceOf(address(this)).add(IStrategy(strategy).estimatedTotalAssets());
    }

    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap, i.e. small
    // users will not have to force strategy withdrawal
    function available() public view returns (uint256) {
        return balance().mul(min).div(MAX);
    }

    // The price in want token of a Vault share
    function getPricePerFullShare() public view returns (uint256) {
        if (totalSupply() == 0) return 1;
        return totalAssets().mul(1e18).div(totalSupply());
    }

    // Deposit all user tokens to the strategy
    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    // Deposit _amount user tokens to the strategy
    function deposit(uint256 _amount) public {
        uint256 _pool = totalAssets();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
    }

    // Send available want tokens to the strategy. Then call deposit() on the strategy
    // With multi-strategy vaults, we check if want == token. Not necessary here, we know they are equal
    function earn() public {
        uint256 _bal = available();
        token.safeTransfer(strategy, _bal);
        IStrategy(strategy).deposit();
    }

    // Withdraw want tokens by burning shares
    // If not enough want tokens are in the Vault, we must call strategy.withdraw()
    function withdraw(uint256 _shares) public {
        uint256 r = (totalAssets().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        uint256 b = token.balanceOf(address(this));

        // If the vault doesn't have enough loose tokens, it must withdraw
        // some from the strategy
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            IStrategy(strategy).withdraw(_withdraw);
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }
        token.safeTransfer(msg.sender, r);
    }

    // Withdraw all of your tokens from the Strategy
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    // Withdraw all tokens from the Strategy
    function withdrawEveryone() public onlyAuthorized {
        IStrategy(strategy).withdrawAll();
    }

    // Withdraw any extra token in VAULT not part of strategy
    function rescueStuckTokens(uint256 _amount, address _token) external onlyAuthorized {
        require(_token != address(token), "Trying to withdraw the want token");
        IERC20(_token).safeTransfer(governance, _amount);
    }

    // TODO - Implement it
    // function getExpectedReturn(
    //     address _strategy,
    //     address _token,
    //     uint256 parts
    // ) public view returns (uint256 expected) {
    //     uint256 _balance = IERC20(_token).balanceOf(_strategy);
    //     address _want = IStrategy(_strategy).want();
    //     (expected, ) = IOneSplitAudit(onesplit).getExpectedReturn(_token, _want, _balance, parts, 0);
    // }
}

