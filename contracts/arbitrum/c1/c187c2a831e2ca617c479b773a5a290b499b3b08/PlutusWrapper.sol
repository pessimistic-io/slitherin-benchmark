// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "./RariVault.sol";
import "./IPlutusWrapper.sol";

// import "forge-std/console2.sol";
import {Math} from "./Math.sol";
import "./SafeERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";


contract PlutusWrapper is IPlutusWrapper, RariVault {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable depositContract;
    address public immutable plvGLP = 0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1; //actual 4626 token
    ERC20 public immutable fsGLP = ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);

    constructor(address _depositContract, ERC20 _asset) RariVault(_asset) {
        depositContract = _depositContract;
        _asset.approve(_depositContract, type(uint256).max);
        ERC20(plvGLP).approve(_depositContract, type(uint256).max);
    }
   
    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual override {
        // shares = previewWithdraw(assets);

        // shares = Math.min(shares, ERC20(plvGLP).balanceOf(address(this)));
        require(shares > 1 ether, "under mint amount");

        if (shares > ERC4626(plvGLP).balanceOf(address(this))) {
            revert NotEnoughAvailableSharesForAmount();
        }

        // console2.log("Shares to withdraw: ", shares);
        // console2.log("Available Shares: ", ERC4626(plvGLP).balanceOf(address(this)));
        // (uint fee, uint rebate) = IglpDepositor(depositContract).getFeeBp(address(this));

        // require(fee > 0, "fee cannot be zero");
        // require(rebate > 0, "fee cannot be zero");


        IglpDepositor(depositContract).redeem(shares);

        // console2.log("GOT HERE");
    }

    function afterDeposit(uint256 assets, uint256 shares) internal virtual override {
        require(assets > 1 ether, "Under min deposit amount");
        IglpDepositor(depositContract).deposit(assets);
    }

    function totalAssets() public view virtual override returns (uint256) {
        // console2.log("Total assets: ", ERC4626(plvGLP).convertToAssets(ERC20(plvGLP).balanceOf(address(this))));
        
        //This is correct - Deposit of 10eth returns 10eth from this method
        return ERC4626(plvGLP).maxWithdraw(address(this));

    }

    // function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
    //     (,,uint256 _assets) = IglpDepositor(depositContract).previewRedeem(address(this), shares);
    //     return _assets;
    // }

    // function previewWithdraw(uint256 _shares) public view virtual override returns (uint256) {
    //     (,,uint256 _assets) = IglpDepositor(depositContract).previewRedeem(address(this), _shares);

    //     uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
    //     uint shares = _assets.mulDivUp(supply, totalAssets());

    //     return shares;
    // }

}
