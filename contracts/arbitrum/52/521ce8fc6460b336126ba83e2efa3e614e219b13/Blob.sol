// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./ERC20Burnable.sol";
import "./Math.sol";
import "./SafeMath8.sol";
import "./Operator.sol";

import "./IOracle.sol";

contract Blob is ERC20Burnable, Operator {
    using SafeMath8 for uint8;
    using SafeMath for uint256;

    // Initial distribution for the first 24h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 1600 ether;
    // Initial distribution for the day 2-5 BLOB-BUSD LP -> BLOB pool
    uint256 public constant INITIAL_BLOB_POOL_DISTRIBUTION = 16200 ether;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;

    // Address of the Oracle
    address public blobOracle;

    /**
     * @notice Constructs the BLOB ERC-20 contract.
     */
    constructor() public ERC20("Blue Lobster", "BLOB") {
        // Mints 1000 BLOB to contract creator for initial pool setup
        _mint(msg.sender, 1000 ether);
    }

    function _getBlobPrice() internal view returns (uint256 _blobPrice) {
        try IOracle(blobOracle).consult(address(this), 1e18) returns (uint144 _price) {
            return uint256(_price);
        } catch {
            revert("Blob: failed to fetch BLOB price from Oracle");
        }
    }

    function setBlobOracle(address _blobOracle) public onlyOperator {
        require(_blobOracle != address(0), "oracle address cannot be 0 address");
        blobOracle = _blobOracle;
    }

    /**
     * @notice Operator mints BLOB to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of BLOB to mint to
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
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address _genesisPool,
        address _blobPool
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_genesisPool != address(0), "!_genesisPool");
        require(_blobPool != address(0), "!_blobPool");
        rewardPoolDistributed = true;
        _mint(_genesisPool, INITIAL_GENESIS_POOL_DISTRIBUTION);
        _mint(_blobPool, INITIAL_BLOB_POOL_DISTRIBUTION);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}
