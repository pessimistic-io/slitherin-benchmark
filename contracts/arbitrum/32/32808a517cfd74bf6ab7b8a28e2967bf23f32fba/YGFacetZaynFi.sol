// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

import {IYGFacetZaynFi} from "./IYGFacetZaynFi.sol";

import {LibYieldGenerationStorage} from "./LibYieldGenerationStorage.sol";
import {LibYieldGeneration} from "./LibYieldGeneration.sol";
import {LibCollateralStorage} from "./LibCollateralStorage.sol";
import {LibDiamond} from "./LibDiamond.sol";

contract YGFacetZaynFi is IYGFacetZaynFi {
    event OnYGOptInToggled(uint indexed termId, address indexed user, bool indexed optedIn); // Emits when a user succesfully toggles yield generation
    event OnYieldClaimed(uint indexed termId, address indexed user, uint indexed amount); // Emits when a user claims their yield

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    /// @notice This function allows a user to claim the current available yield
    /// @param termId The term id for which the yield is being claimed
    function claimAvailableYield(uint termId) external {
        _claimAvailableYield(termId, msg.sender);
    }

    /// @notice This function allows a user to claim the current available yield
    /// @param termId The term id for which the yield is being claimed
    /// @param user The user address that is claiming the yield
    function claimAvailableYield(uint termId, address user) external {
        _claimAvailableYield(termId, user);
    }

    function toggleOptInYG(uint termId) external {
        LibYieldGenerationStorage.YieldGeneration storage yield = LibYieldGenerationStorage
            ._yieldStorage()
            .yields[termId];
        LibCollateralStorage.Collateral storage collateral = LibCollateralStorage
            ._collateralStorage()
            .collaterals[termId];

        require(LibYieldGenerationStorage._yieldExists(termId));
        require(
            collateral.state == LibCollateralStorage.CollateralStates.AcceptingCollateral,
            "Too late to change YG opt in"
        );
        require(
            collateral.isCollateralMember[msg.sender],
            "Pay the collateral security deposit first"
        );

        bool optIn = !yield.hasOptedIn[msg.sender];
        yield.hasOptedIn[msg.sender] = optIn;
        emit OnYGOptInToggled(termId, msg.sender, optIn);
    }

    function updateYieldProvider(
        string memory providerString,
        address providerAddress
    ) external onlyOwner {
        LibYieldGenerationStorage.YieldProviders storage yieldProvider = LibYieldGenerationStorage
            ._yieldProviders();

        yieldProvider.providerAddresses[providerString] = providerAddress;
    }

    function _claimAvailableYield(uint termId, address user) internal {
        LibYieldGenerationStorage.YieldGeneration storage yield = LibYieldGenerationStorage
            ._yieldStorage()
            .yields[termId];

        uint availableYield = yield.availableYield[user];

        require(availableYield > 0, "No yield to withdraw");

        yield.availableYield[user] = 0;
        (bool success, ) = payable(user).call{value: availableYield}("");
        require(success);

        emit OnYieldClaimed(termId, user, availableYield);
    }

    function toggleYieldLock() external onlyOwner returns (bool) {
        bool newYieldLock = !LibYieldGenerationStorage._yieldLock().yieldLock;
        LibYieldGenerationStorage._yieldLock().yieldLock = newYieldLock;

        return LibYieldGenerationStorage._yieldLock().yieldLock;
    }
}

