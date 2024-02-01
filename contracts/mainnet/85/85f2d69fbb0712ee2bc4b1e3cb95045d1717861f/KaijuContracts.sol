// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./IDNA.sol";
import "./IRWaste.sol";
import "./IScales.sol";
import "./IMutants.sol";

library KaijuContracts {
	struct Contracts {
		IDNA DNA;
		IRWaste RWaste;
		IScales Scales;
		IMutants Mutant;
	}
}

