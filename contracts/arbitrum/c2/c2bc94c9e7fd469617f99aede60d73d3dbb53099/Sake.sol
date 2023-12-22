//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

// import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {IVault} from "./IVault.sol";
import {ITokenFarm} from "./ITokenFarm.sol";

/**
 * @author Chef Photons, Vaultka Team serving high quality drinks; drink responsibly.
 * Responsible for to keeping track of our finest Sake
 */
contract Sake is Ownable {
    IERC20 private immutable usdcToken;
    address private immutable bartender;
    address private immutable water;
    uint256 private totalAmountOfVLP;
    address private liquor;

    //vela exchange contracts
    //will keep these
    IVault private immutable velaMintBurnVault;
    ITokenFarm private immutable velaStakingVault;
    IERC20 private immutable vlp;

    event Withdraw(address indexed _user, uint256 _amount);

    error ThrowPermissionDenied(address admin, address sender);

    modifier onlyBartenderOrLiquor() {
        if (_msgSender() != address(bartender) && _msgSender() != address(liquor))
            revert ThrowPermissionDenied({admin: address(bartender), sender: _msgSender()});
        _;
    }

    constructor(
        address _usdcToken,
        address _water,
        address _bartender,
        address _velaMintBurnVault,
        address _velaStakingVault,
        address _vlp,
        address _liquor
    ) {
        usdcToken = IERC20(_usdcToken);
        water = _water;
        bartender = _bartender;
        velaMintBurnVault = IVault(_velaMintBurnVault);
        velaStakingVault = ITokenFarm(_velaStakingVault);
        vlp = IERC20(_vlp);
        liquor = _liquor;
    }

    //@todo some approval needs to be grant for deposit and withdrawal, will work on that later

    /// @notice allows bartender to mint and stake vlp into the sake contract
    /// @return status status is true if the function executed sucessfully, vice versa
    function executeMintAndStake() external onlyBartenderOrLiquor returns (bool status, uint256 totalVLP) {
        uint256 usdcBalance = usdcToken.balanceOf(address(this));
        usdcToken.approve(address(velaMintBurnVault), usdcBalance);
        // vlp approve staking vault with uint256 max
        vlp.approve(address(velaStakingVault), type(uint256).max);
        //mint the whole batch of USDC to VLP, sake doesn't handle the accounting, so balanceOf will be sufficient.
        // @notice there is no need for reentrancy guard Bartender will handle that
        // REFERENCE: 01
        // @todo a struct/variables to store or return this values so that bartender can store them to calculate user share during withdrawal
        // vlp recieved,
        // amount used to purchase the vlp, (can be excluded since it amount transfered by bartender to sake)
        // price at which vlp was bought
        velaMintBurnVault.stake(address(this), address(usdcToken), usdcBalance);
        // get the total amount of VLP bought
        totalVLP = vlp.balanceOf(address(this));
        totalAmountOfVLP = totalVLP;
        velaStakingVault.deposit(0, totalVLP);

        return (true, totalVLP);
    }

    /// @notice allows bartender to withdraw a specific amount from the sake contract
    /// @param _to user reciving the redeemed USDC
    /// @param amountToWithdrawInVLP amount to withdraw in VLP
    /// @return status received in exchange of token
    function withdraw(
        address _to,
        uint256 amountToWithdrawInVLP
    ) external onlyBartenderOrLiquor returns (bool status, uint256 usdcAmount) {
        vlp.approve(address(velaStakingVault), amountToWithdrawInVLP);
        velaStakingVault.withdraw(0, amountToWithdrawInVLP);
        velaMintBurnVault.unstake(address(usdcToken), amountToWithdrawInVLP, address(this));
        uint256 withdrawAmount = usdcToken.balanceOf(address(this));

        //sake will send the USDC back to the user directly
        usdcToken.transfer(_to, withdrawAmount);
        return (true, withdrawAmount);
    }

    // create a function to output sake balance in vlp
    function getSakeBalanceInVLP() external view returns (uint256 vlpBalance) {
        return totalAmountOfVLP;
    }

    function getClaimable() public view returns (uint256) {
        return velaStakingVault.claimable(address(this));
    }

    function withdrawVesting() external onlyBartenderOrLiquor {
        velaStakingVault.withdrawVesting();
    }
}

