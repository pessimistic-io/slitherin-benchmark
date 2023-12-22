// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./IERC20Upgradeable.sol";
import "./IArbitrumTimelock.sol";
import "./IFixedDelegateErc20Wallet.sol";
import "./IL2ArbitrumToken.sol";
import "./IL2ArbitrumGovernor.sol";
import "./IArbitrumDAOConstitution.sol";

interface ICoreGovTimelockGetter {
    function coreGovTimelock() external view returns (IArbitrumTimelock);
}

interface ICoreGovGetter {
    function coreGov() external view returns (IL2ArbitrumGoverner);
}

interface ITreasuryGovTimelockGetter {
    function treasuryGovTimelock() external view returns (IArbitrumTimelock);
}

interface ITreasuryGovGetter {
    function treasuryGov() external view returns (IL2ArbitrumGoverner);
}

interface IDaoTreasuryGetter {
    function treasuryWallet() external view returns (IFixedDelegateErc20Wallet);
}

interface IL2ArbitrumTokenGetter {
    function l2ArbitrumToken() external view returns (IL2ArbitrumToken);
}

interface IArbitrumDAOConstitutionGetter {
    function arbitrumDAOConstitution() external view returns (IArbitrumDAOConstitution);
}

interface IL2AddressRegistry is
    ICoreGovGetter,
    ICoreGovTimelockGetter,
    ITreasuryGovTimelockGetter,
    IDaoTreasuryGetter,
    ITreasuryGovGetter,
    IL2ArbitrumTokenGetter,
    IArbitrumDAOConstitutionGetter
{}

