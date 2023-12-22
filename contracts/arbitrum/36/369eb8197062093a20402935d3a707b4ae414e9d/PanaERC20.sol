// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./SafeMath.sol";

import "./IERC20.sol";
import "./IPana.sol";
import "./IERC20Permit.sol";

import "./ERC20Permit.sol";
import "./PanaAccessControlled.sol";

contract PanaERC20Token is ERC20Permit, IPana, PanaAccessControlled {
    using SafeMath for uint256;

    bool public distributionConcluded;
    uint256 public totalDistributed;

    constructor(address _authority) 
    ERC20("Pana DAO", "PANA", 18) 
    ERC20Permit("Pana DAO") 
    PanaAccessControlled(IPanaAuthority(_authority)) {}

    function mint(address account_, uint256 amount_) external override onlyVault {
        _mint(account_, amount_);
    }

    /**
     * @notice mints Pana to the distribution vault
     */
    function mintForDistribution(uint256 amount_) external onlyGovernor {
        require(authority.distributionVault() != address(0), "Zero address: distributionVault");
        require(!distributionConcluded, "Distribution concluded");

        totalDistributed += amount_;
        _mint(authority.distributionVault(), amount_);
    }

    /**
     * @notice concludes token launch Pana distribution.
     * This effectively turns the possibility to mint Pana via mintForDistribution() off.
     * distributionConcluded is one-way switch and it cannot be turned on again.
     */
    function concludeDistribution() external onlyGovernor {
        require(!distributionConcluded, "Already concluded");

        distributionConcluded = true;
        emit DistributionConcluded(totalDistributed);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) external override {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) internal {
        uint256 decreasedAllowance_ = allowance(account_, msg.sender).sub(amount_, "ERC20: burn amount exceeds allowance");

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }
}

