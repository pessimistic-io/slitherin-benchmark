// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./ERC20.sol";
import "./LedgerOwner.sol";
import "./Errors.sol";
import "./BrightPoolWarden.sol";

contract BRI is ERC20, LedgerOwner {
    uint256 constant BRI_HARD_CAP = 5_000_000_000 gwei;

    uint256 constant MINIMUM_KILL_COOLDOWN = 24 hours;

    /**
     * @dev The event emitted on new oracle is set.
     *
     * @param oracle New oracle address set
     */
    event NewOracle(address indexed oracle);

    /**
     * @dev The event emitted on new tokens being minted.
     *
     * @param recipient The recipient of newly minted tokens
     * @param amount The amount of tokens being minted
     */
    event BridgedIn(address indexed recipient, uint256 amount);

    /**
     * @dev The event emitted on tokens being burnt.
     *
     * @param source The source account of tokens burnt
     * @param amount The amount of tokens being burnt
     */
    event BridgedOut(address indexed source, uint256 amount);

    /**
     * @dev The event emitted on new tokens being minted as rewards.
     *
     * @param recipient The recipient of newly minted tokens
     * @param amount The amount of tokens being minted
     */
    event Rewarded(address indexed recipient, uint256 amount);

    /**
     * @dev The event emitted on tokens being burnt on reward cancellation.
     *
     * @param source The source account of tokens burnt
     * @param amount The amount of tokens being burnt
     */
    event RewardCancelled(address indexed source, uint256 amount);

    /**
     * @dev The event emitted upon kill switch set
     *
     * @param deadline The deadline of killswitch set
     */
    event TransfersKilled(uint256 deadline);

    /**
     * @dev The oracle address that is allowed to mint and burn tokens as bridging between blockchains
     */
    address public oracle;

    /**
     * @dev The date the kill switch has been moved
     */
    uint256 killSwitch;

    /**
     * @dev The modifier restricting method to be run by oracle address only
     */
    modifier onlyOracle() {
        if (_msgSender() != oracle) revert Restricted();
        _;
    }

    /**
     * @dev Token constructor.
     *
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param owner_ The owner of the contract
     * @param admin_ The administrator of the contact (allowed to kill transfers)
     * @param oracle_ The oracle that is allowed to mint and burn tokens
     * @param initialMint_ The initial mint created by the owner - deployer
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        address admin_,
        address oracle_,
        uint256 initialMint_,
        BrightPoolWarden warden_
    ) ERC20(name_, symbol_) LedgerOwner(owner_, admin_, warden_) {
        if (oracle_ == address(0)) revert ZeroAddress();
        _mint(owner_, initialMint_);
        oracle = oracle_;
    }

    /**
     * @dev Complying to BEP-20 standard - delivering the address of token owner
     */
    function getOwner() external view returns (address) {
        return owner();
    }

    /**
     * @dev Sets decimal places for token to just 9 places instead of default 18
     */
    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    /**
     * @dev Method changing an oracle. Only contract owner can do that.
     *
     * The change of the oracle is possible only during BRI lock
     *
     * @param oracle_ New contract oracle. Might be address(0) to stop mint/burning mechanism.
     */
    function setOracle(address oracle_) external onlyAdminOrOwner {
        if (oracle_ == oracle) revert AlreadySet();

        // slither-disable-start reentrancy-events
        // slither-disable-next-line reentrancy-no-eth
        if (_getWarden().changeValue(oracle_, "oracle", msg.sender)) {
            oracle = oracle_;
            emit NewOracle(oracle_);
        }
        // slither-disable-end reentrancy-events
    }

    /**
     * @dev Method allowing the oracle to mint new tokens.
     *
     * @param recipient_ The recipient of the newly minted tokens.
     * @param amount_ The amount of tokens being minted.
     */
    function bridgeIn(address recipient_, uint256 amount_) external onlyOracle {
        if (totalSupply() + amount_ > BRI_HARD_CAP) revert CapExceeded();
        _mint(recipient_, amount_);
        emit BridgedIn(recipient_, amount_);
    }

    /**
     * @dev Method allowing the oracle to burn tokens.
     *
     * @param source_ The source of the tokens being burnt.
     * @param amount_ The amount of tokens being burnt.
     */
    function bridgeOut(address source_, uint256 amount_) external onlyOracle {
        _burn(source_, amount_);
        emit BridgedOut(source_, amount_);
    }

    /**
     * @dev Method allowing the ledger to mint new tokens.
     *
     * @param recipient_ The recipient of the newly minted tokens.
     * @param amount_ The amount of tokens being minted.
     */
    function reward(address recipient_, uint256 amount_) external onlyLedger {
        if (totalSupply() + amount_ > BRI_HARD_CAP) revert CapExceeded();
        _mint(recipient_, amount_);
        emit Rewarded(recipient_, amount_);
    }

    /**
     * @dev Method allowing the ledger to burn tokens.
     *
     * @param source_ The source of the tokens being burnt.
     * @param amount_ The amount of tokens being burnt.
     */
    function cancelReward(address source_, uint256 amount_) external onlyLedger {
        _burn(source_, amount_);
        emit RewardCancelled(source_, amount_);
    }

    /**
     * @dev Owners method to kill any transfers for token until given time (not more than 24h)
     *
     * @param deadlineInHours_ Amount of hours to kill the transfers for
     */
    function killTransfers(uint256 deadlineInHours_) external onlyAdmin {
        // slither-disable-next-line timestamp
        if (killSwitch >= block.timestamp) revert KillSwitch();
        // slither-disable-next-line timestamp
        if (killSwitch + MINIMUM_KILL_COOLDOWN >= block.timestamp) revert Restricted();
        // slither-disable-next-line timestamp
        if (deadlineInHours_ == 0 || deadlineInHours_ > 24) revert WrongDeadline();

        killSwitch = block.timestamp + deadlineInHours_ * (1 hours);

        emit TransfersKilled(killSwitch);
    }

    /**
     * @dev Transfer checker
     */
    function _beforeTokenTransfer(address, address, uint256) internal virtual override {
        // slither-disable-next-line timestamp
        if (killSwitch > block.timestamp) revert KillSwitch();
    }
}

