// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./BancorFormula.sol";
import "./IOracle.sol";
import "./IVaultCore.sol";
import "./StableMath.sol";


/**
 * @title supporting VaultCore of USDs protocol
 * @dev calculation of chi, swap fees associated with USDs's mint and redeem
 * @dev view functions of USDs's mint and redeem
 * @author Sperax Foundation
 */
contract VaultCoreTools is Initializable {
	using SafeERC20Upgradeable for ERC20Upgradeable;
	using SafeMathUpgradeable for uint;
	using StableMath for uint;

	BancorFormula public BancorInstance;

	function initialize(address _BancorFormulaAddr) public initializer {
		BancorInstance = BancorFormula(_BancorFormulaAddr);
	}

	/**
	 * @dev calculate chiTarget by the formula in section 2.2 of the whitepaper
	 * @param blockPassed the number of blocks that have passed since USDs is launched, i.e. "Block Height"
	 * @param priceUSDs the price of USDs, i.e. "USDs Price"
	 * @param precisionUSDs the precision used in the variable "priceUSDs"
	 * @return chiTarget_ the value of chiTarget
	 */
	function chiTarget(
			uint blockPassed, uint priceUSDs, uint precisionUSDs, address _VaultCoreContract
		) public view returns (uint chiTarget_) {
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		uint chiAdjustmentA = blockPassed.mul(_vaultContract.chi_alpha());
		uint afterB;
		if (priceUSDs >= precisionUSDs) {
			uint chiAdjustmentB = uint(_vaultContract.chi_beta())
				.mul(uint(_vaultContract.chi_prec()))
				.mul(priceUSDs - precisionUSDs)
				.mul(priceUSDs - precisionUSDs);
			chiAdjustmentB = chiAdjustmentB
				.div(_vaultContract.chi_beta_prec())
				.div(precisionUSDs)
				.div(precisionUSDs);
			afterB = _vaultContract.chiInit().add(chiAdjustmentB);
		} else {
			uint chiAdjustmentB = uint(_vaultContract.chi_beta())
				.mul(uint(_vaultContract.chi_prec()))
				.mul(precisionUSDs - priceUSDs)
				.mul(precisionUSDs - priceUSDs);
			chiAdjustmentB = chiAdjustmentB
				.div(_vaultContract.chi_beta_prec())
				.div(precisionUSDs)
				.div(precisionUSDs);
			(, afterB) = _vaultContract.chiInit().trySub(chiAdjustmentB);
		}
		(, chiTarget_) = afterB.trySub(chiAdjustmentA);
		if (chiTarget_ > _vaultContract.chi_prec()) {
			chiTarget_ = _vaultContract.chi_prec();
		}
	}

	function multiplier(uint original, uint price, uint precision) public pure returns (uint) {
		return original.mul(price).div(precision);
	}

	/**
	 * @dev calculate chiMint
	 * @return chiMint, i.e. chiTarget, since they share the same value
	 */
	function chiMint(address _VaultCoreContract) public view returns (uint)	{
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		uint priceUSDs = uint(IOracle(_vaultContract.oracleAddr()).getUSDsPrice());
		uint precisionUSDs = IOracle(_vaultContract.oracleAddr()).getUSDsPrice_prec();
		uint blockPassed = uint(block.number).sub(_vaultContract.startBlockHeight());
		return chiTarget(blockPassed, priceUSDs, precisionUSDs, _VaultCoreContract);
	}


	/**
	 * @dev calculate chiRedeem based on the formula at the end of section 2.2
	 * @return chiRedeem_
	 */
	function chiRedeem(address _VaultCoreContract) public view returns (uint chiRedeem_) {
		// calculate chiTarget
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		uint priceUSDs = uint(IOracle(_vaultContract.oracleAddr()).getUSDsPrice());
		uint precisionUSDs = IOracle(_vaultContract.oracleAddr()).getUSDsPrice_prec();
		uint blockPassed = uint(block.number).sub(_vaultContract.startBlockHeight());
		uint chiTarget_ = chiTarget(blockPassed, priceUSDs, precisionUSDs, _VaultCoreContract);
		// calculate chiRedeem
		uint collateralRatio_ = _vaultContract.collateralRatio();
		if (chiTarget_ > collateralRatio_) {
			chiRedeem_ = chiTarget_.sub(uint(_vaultContract.chi_gamma()).mul(chiTarget_ - collateralRatio_).div(uint(_vaultContract.chi_gamma_prec())));
		} else {
			chiRedeem_ = chiTarget_;
		}
	}


	/**
	 * @dev calculate the OutSwap fee, i.e. fees for redeeming USDs
	 * @return the OutSwap fee
	 */
	function calculateSwapFeeOut(address _VaultCoreContract) public view returns (uint) {
		// if the OutSwap fee is diabled, return 0
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		if (!_vaultContract.swapfeeOutAllowed()) {
			return 0;
		}
		// implement the formula in Section 4.3.2 of whitepaper
		uint USDsInOutRatio = IOracle(_vaultContract.oracleAddr()).USDsInOutRatio();
		uint32 USDsInOutRatio_prec = IOracle(_vaultContract.oracleAddr()).USDsInOutRatio_prec();
		if (USDsInOutRatio <= uint(_vaultContract.swapFee_a()).mul(uint(USDsInOutRatio_prec)).div(uint(_vaultContract.swapFee_a_prec()))) {
			return uint(_vaultContract.swapFee_prec()) / 1000; //0.1%
		} else {
			uint exponentWithPrec = USDsInOutRatio - uint(_vaultContract.swapFee_a()).mul(uint(USDsInOutRatio_prec)).div(uint(_vaultContract.swapFee_a_prec()));
			if (exponentWithPrec >= 2^32) {
				return uint(15000000000); // 1.5%
			}
			(uint powResWithPrec, uint8 powResPrec) = BancorInstance.power(
				uint(_vaultContract.swapFee_A()), uint(_vaultContract.swapFee_A_prec()), uint32(exponentWithPrec), USDsInOutRatio_prec
			);
			uint toReturn = uint(powResWithPrec.mul(uint(_vaultContract.swapFee_prec())) >> powResPrec) / 100;
			if (toReturn >= uint(15000000000)) {
				return uint(15000000000); // 1.5%
			} else {
				return toReturn;
			}
		}
	}

	function redeemView(
		address _collaAddr,
		uint USDsAmt,
		address _VaultCoreContract,
		address _oracleAddr
	) public view returns (uint SPAMintAmt, uint collaUnlockAmt, uint USDsBurntAmt, uint swapFeeAmount) {
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		uint swapFee = calculateSwapFeeOut(_VaultCoreContract);
		collaUnlockAmt = 0;
		USDsBurntAmt = 0;
		swapFeeAmount = 0;
		SPAMintAmt = multiplier(USDsAmt, (uint(_vaultContract.chi_prec()) - chiRedeem(_VaultCoreContract)), uint(_vaultContract.chi_prec()));
		SPAMintAmt = multiplier(SPAMintAmt, IOracle(_oracleAddr).getSPAprice_prec(), IOracle(_oracleAddr).getSPAprice());
		if (swapFee > 0) {
			SPAMintAmt = SPAMintAmt.sub(multiplier(SPAMintAmt, swapFee, uint(_vaultContract.swapFee_prec())));
		}

		// Unlock collaeral
		collaUnlockAmt = multiplier(USDsAmt, chiRedeem(_VaultCoreContract), uint(_vaultContract.chi_prec()));
		collaUnlockAmt = multiplier(collaUnlockAmt, IOracle(_oracleAddr).getCollateralPrice_prec(_collaAddr), IOracle(_oracleAddr).getCollateralPrice(_collaAddr));
		collaUnlockAmt = collaUnlockAmt.div(10**(uint(18).sub(uint(ERC20Upgradeable(_collaAddr).decimals()))));

		if (swapFee > 0) {
			collaUnlockAmt = collaUnlockAmt.sub(multiplier(collaUnlockAmt, swapFee, uint(_vaultContract.swapFee_prec())));
		}

		// //Burn USDs
		swapFeeAmount = multiplier(USDsAmt, swapFee, uint(_vaultContract.swapFee_prec()));
		USDsBurntAmt = USDsAmt.sub(swapFeeAmount);
	}

	/**
	 * @dev calculate the InSwap fee, i.e. fees for minting USDs
	 * @return the InSwap fee
	 */
	function calculateSwapFeeIn(address _VaultCoreContract) public view returns (uint) {
		// if InSwap fee is disabled, return 0
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		if (!_vaultContract.swapfeeInAllowed()) {
			return 0;
		}

		// implement the formula in Section 4.3.1 of whitepaper
		uint priceUSDs_Average = IOracle(_vaultContract.oracleAddr()).getUSDsPrice_average();
		uint precisionUSDs = IOracle(_vaultContract.oracleAddr()).getUSDsPrice_prec();
		uint smallPwithPrecision = uint(_vaultContract.swapFee_p()).mul(precisionUSDs).div(_vaultContract.swapFee_p_prec());
		uint swapFee_prec = uint(_vaultContract.swapFee_prec());
		if (smallPwithPrecision < priceUSDs_Average) {
			return swapFee_prec / 1000; // 0.1%
		} else {
			uint temp = (smallPwithPrecision - priceUSDs_Average).mul(_vaultContract.swapFee_theta()).div(_vaultContract.swapFee_theta_prec()); //precision: precisionUSDs
			uint temp2 = temp.mul(temp); //precision: precisionUSDs^2
			uint temp3 = temp2.mul(swapFee_prec).div(precisionUSDs).div(precisionUSDs);
			uint temp4 = temp3.div(100);
			uint temp5 = swapFee_prec / 1000 + temp4;
			if (temp5 >= uint(15000000000)) {
				return uint(15000000000); // 1.5%
			} else {
				return temp5;
			}
		}
	}

	/**
	 * @dev the general mintView function that display all related quantities based on mint types
	 *		valueType = 0: mintWithUSDs
	 *		valueType = 1: mintWithSPA
	 *		valueType = 2: mintWithColla
	 * @param collaAddr the address of user's chosen collateral
	 * @param valueAmt the amount of user input whose specific meaning depends on valueType
	 * @param valueType the type of user input whose interpretation is listed above in @dev
	 * @return SPABurnAmt the amount of SPA to burn
	 *			collaDeptAmt the amount of collateral to stake
	 *			USDsAmt the amount of USDs to mint
	 *			swapFeeAmount the amount of Inswapfee to pay
	 */
	function mintView(
		address collaAddr,
		uint valueAmt,
		uint8 valueType,
		address _VaultCoreContract
	) public view returns (uint SPABurnAmt, uint collaDeptAmt, uint USDsAmt, uint swapFeeAmount) {
		// obtain the price and pecision of the collateral
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);

		// obtain other necessary data
		uint swapFee = calculateSwapFeeIn(_VaultCoreContract);

		if (valueType == 0) { // when mintWithUSDs
			// calculate USDsAmt
			USDsAmt = valueAmt;
			// calculate SPABurnAmt
			SPABurnAmt = SPAAmountCalculator(valueType, USDsAmt, _VaultCoreContract, swapFee);
			// calculate collaDeptAmt
			collaDeptAmt = collaDeptAmountCalculator(valueType, USDsAmt, _VaultCoreContract, collaAddr, swapFee);

			// calculate swapFeeAmount
			swapFeeAmount = USDsAmt.mul(swapFee).div(uint(_vaultContract.swapFee_prec()));

		} else if (valueType == 1) { // when mintWithSPA
			// calculate SPABurnAmt
			SPABurnAmt = valueAmt;
			// calculate USDsAmt
			USDsAmt = USDsAmountCalculator(valueType, valueAmt, _VaultCoreContract, collaAddr, swapFee);
			// calculate collaDeptAmt

			collaDeptAmt = collaDeptAmountCalculator(valueType, USDsAmt, _VaultCoreContract, collaAddr, swapFee);
			// calculate swapFeeAmount
			swapFeeAmount = USDsAmt.mul(swapFee).div(uint(_vaultContract.swapFee_prec()));

		} else if (valueType == 2) { // when mintWithColla
			// calculate collaDeptAmt
			collaDeptAmt = valueAmt;
			// calculate USDsAmt
			USDsAmt = USDsAmountCalculator(valueType, valueAmt, _VaultCoreContract, collaAddr, swapFee);
			// calculate SPABurnAmt
			SPABurnAmt = SPAAmountCalculator(valueType, USDsAmt, _VaultCoreContract, swapFee);
			// calculate swapFeeAmount
			swapFeeAmount = USDsAmt.mul(swapFee).div(uint(_vaultContract.swapFee_prec()));
		}
	}

	function collaDeptAmountCalculator(
		uint valueType, uint USDsAmt, address _VaultCoreContract, address collaAddr, uint swapFee
	) public view returns (uint256 collaDeptAmt) {
		require(valueType == 0 || valueType == 1, 'invalid valueType');
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		uint collaAddrDecimal = uint(ERC20Upgradeable(collaAddr).decimals());
		if (valueType == 1) {
			collaDeptAmt = USDsAmt.mul(chiMint(_VaultCoreContract)).mul(IOracle(_vaultContract.oracleAddr()).getCollateralPrice_prec(collaAddr)).div(uint(_vaultContract.chi_prec()).mul(IOracle(_vaultContract.oracleAddr()).getCollateralPrice(collaAddr))).div(10**(uint(18).sub(collaAddrDecimal)));
			if (swapFee > 0) {
				collaDeptAmt = collaDeptAmt.add(collaDeptAmt.mul(swapFee).div(uint(_vaultContract.swapFee_prec())));
			}
		} else if (valueType == 0) {
			collaDeptAmt = USDsAmt.mul(chiMint(_VaultCoreContract)).mul(IOracle(_vaultContract.oracleAddr()).getCollateralPrice_prec(collaAddr)).div(uint(_vaultContract.chi_prec()).mul(IOracle(_vaultContract.oracleAddr()).getCollateralPrice(collaAddr))).div(10**(uint(18).sub(collaAddrDecimal)));
			if (swapFee > 0) {
				collaDeptAmt = collaDeptAmt.add(collaDeptAmt.mul(swapFee).div(uint(_vaultContract.swapFee_prec())));
			}
		}
	}

	function SPAAmountCalculator(
		uint valueType, uint USDsAmt, address _VaultCoreContract, uint swapFee
	) public view returns (uint256 SPABurnAmt) {
		require(valueType == 0 || valueType == 2, 'invalid valueType');
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		uint priceSPA = IOracle(_vaultContract.oracleAddr()).getSPAprice();
		uint precisionSPA = IOracle(_vaultContract.oracleAddr()).getSPAprice_prec();
		SPABurnAmt = USDsAmt.mul(uint(_vaultContract.chi_prec()) - chiMint(_VaultCoreContract)).mul(precisionSPA).div(priceSPA.mul(uint(_vaultContract.chi_prec())));
		if (swapFee > 0) {
			SPABurnAmt = SPABurnAmt.add(SPABurnAmt.mul(swapFee).div(uint(_vaultContract.swapFee_prec())));
		}
	}

	function USDsAmountCalculator(
		uint valueType, uint valueAmt, address _VaultCoreContract, address collaAddr, uint swapFee
	) public view returns (uint256 USDsAmt) {
		require(valueType == 1 || valueType == 2, 'invalid valueType');
		IVaultCore _vaultContract = IVaultCore(_VaultCoreContract);
		uint priceSPA = IOracle(_vaultContract.oracleAddr()).getSPAprice();
		uint precisionSPA = IOracle(_vaultContract.oracleAddr()).getSPAprice_prec();
		if (valueType == 2) {
			USDsAmt = valueAmt;
			if (swapFee > 0) {
				USDsAmt = USDsAmt.mul(uint(_vaultContract.swapFee_prec())).div(uint(_vaultContract.swapFee_prec()).add(swapFee));
			}
			USDsAmt = USDsAmt.mul(10**(uint(18).sub(uint(ERC20Upgradeable(collaAddr).decimals())))).mul(uint(_vaultContract.chi_prec()).mul(IOracle(_vaultContract.oracleAddr()).getCollateralPrice(collaAddr))).div(IOracle(_vaultContract.oracleAddr()).getCollateralPrice_prec(collaAddr)).div(chiMint(_VaultCoreContract));
		} else if (valueType == 1) {
			USDsAmt = valueAmt;
			if (swapFee > 0) {
				USDsAmt = USDsAmt.mul(uint(_vaultContract.swapFee_prec())).div(uint(_vaultContract.swapFee_prec()).add(swapFee));
			}
			USDsAmt = USDsAmt.mul(uint(_vaultContract.chi_prec())).mul(priceSPA).div(precisionSPA.mul(uint(_vaultContract.chi_prec()) - chiMint(_VaultCoreContract)));
		}
	}
}

