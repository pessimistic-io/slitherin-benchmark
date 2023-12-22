// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./ERC20Burnable.sol";
import "./Math.sol";
import "./SafeMath8.sol";
import "./Operator.sol";

import "./IOracle.sol";

contract Mango is ERC20Burnable, Operator {
    using SafeMath8 for uint8;
    using SafeMath for uint256;

    // Initial distribution for the first 24h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 1800 ether;
    
    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;
    bool public marketEnabled = false;

    mapping (address => bool) public blacklist;

    /**
     * @notice Constructs the MANGO ERC-20 contract.
     */
    constructor() public ERC20("Mango Token", "MANGO") {
        // Mints 1000 MANGO to contract creator for initial pool setup
        _mint(msg.sender, 1000 ether);
    }

    /**
     * @notice Operator mints MANGO to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of MANGO to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        if( sender != owner() && recipient != owner())
            require(marketEnabled, "mango: market not enabled");

        require(!blacklist[sender] && !blacklist[recipient], "mango: blacklisted");

        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    
    function enableMarket(bool _flg) public onlyOwner {
        marketEnabled = _flg;
    }

    function setBlacklist(address _account, bool _flg) public onlyOwner {
        blacklist[_account] = _flg;
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address _genesisPool
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_genesisPool != address(0), "!_genesisPool");
        rewardPoolDistributed = true;
        _mint(_genesisPool, INITIAL_GENESIS_POOL_DISTRIBUTION);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}
