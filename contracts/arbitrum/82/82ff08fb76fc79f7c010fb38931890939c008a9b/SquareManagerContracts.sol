//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./SquareManagerState.sol";

abstract contract SquareManagerContracts is Initializable, SquareManagerState {
    function __SquareManagerContracts_init() internal initializer {
        SquareManagerState.__SquareManagerState_init();
    }
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function setContracts(
        address _squareAddress,
        address _squareInterface,
        address _randomizerAddress,
        address _magicAddress) 
        external 
        onlyAdminOrOwner 
    {
        square = IERC721Upgradeable(_squareAddress);
        iSquare = ISquare(_squareInterface);
    }
    
    modifier contractsAreSet() {
		require(areContractsSet(), "SquareManager: Contracts aren't set");
		_;
	}

	function areContractsSet() public view returns (bool) {
        return address(square) != address(0)
            && address(iSquare) != address(0);
	}

    function setFreeze(bool _freeze) 
        external
        onlyAdminOrOwner
    {
        freeze = _freeze;
    }

    modifier contractNotFrozen() {
        require(!freeze, "SquareManager: Contract currently frozen");
        _;
    }

    modifier tableNotSet() {
        require(!tableSet, "SquareManager: Table already set");
        _;
    }
}

