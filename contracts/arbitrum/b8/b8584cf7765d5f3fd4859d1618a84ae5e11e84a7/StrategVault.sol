/**
 * SPDX-License-Identifier: Proprietary
 * 
 * Strateg Protocol contract
 * PROPRIETARY SOFTWARE AND LICENSE. 
 * This contract is the valuable and proprietary property of Strateg Development Association. 
 * Strateg Development Association shall retain exclusive title to this property, and all modifications, 
 * implementations, derivative works, upgrades, productizations and subsequent releases. 
 * To the extent that developers in any way contributes to the further development of Strateg protocol contracts, 
 * developers hereby irrevocably assign and/or agrees to assign all rights in any such contributions or further developments to Strateg Development Association. 
 * Without limitation, Strateg Development Association acknowledges and agrees that all patent rights, 
 * copyrights in and to the Strateg protocol contracts shall remain the exclusive property of Strateg Development Association at all times.
 * 
 * DEVELOPERS SHALL NOT, IN WHOLE OR IN PART, AT ANY TIME: 
 * (i) SELL, ASSIGN, LEASE, DISTRIBUTE, OR OTHER WISE TRANSFER THE STRATEG PROTOCOL CONTRACTS TO ANY THIRD PARTY; 
 * (ii) COPY OR REPRODUCE THE STRATEG PROTOCOL CONTRACTS IN ANY MANNER;
 */
pragma solidity ^0.8.15;

import "./ERC20.sol";
import "./IERC20Metadata.sol";
import "./ERC4626.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./IStrategStepRegistry.sol";
import "./IStratStep.sol";

import "./console.sol";

contract StrategVault is ERC20, ERC20Permit, ERC4626, Ownable {
    bool public initialized;
    address public registry;
    address public feeCollector;
    address public factory;
    uint256 private performanceFees;
    uint256 private lastFeeHarvestIndex;

    uint16 private stratStepsLength;
    mapping(uint16 => address) private stratSteps;
    mapping(uint16 => bytes) private stratStepsParameters;

    uint16 private harvestStepsLength;
    mapping(uint16 => address) private harvestSteps;
    mapping(uint16 => bytes) private harvestStepsParameters;

    uint16 private oracleStepsLength;
    mapping(uint16 => address) private oracleSteps;
    mapping(uint16 => bytes) private oracleStepsParameters;

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(
        address _feeCollector,
        address _registry,
        string memory _name,
        string memory _symbol,
        address asset,
        uint256 _performanceFees
    ) ERC20(_name, _symbol) ERC20Permit(_name) ERC4626(IERC20Metadata(asset)) {
        registry = _registry;
        performanceFees = _performanceFees; // 10000 = 100%
        feeCollector = _feeCollector;
        lastFeeHarvestIndex = 10000;
        factory = msg.sender;
    }

    function setStrat(
        uint256[] memory _stratStepsIndex,
        bytes[] memory _stratStepsParameters,
        uint256[] memory _harvestStepsIndex,
        bytes[] memory _harvestStepsParameters,
        uint256[] memory _oracleStepsIndex,
        bytes[] memory _oracleStepsParameters
    ) external onlyOwner {
        require(!initialized, 'initialized');
        // console.log("Entering in function");
        IStrategyStepRegistry r = IStrategyStepRegistry(registry);
        address[] memory _stratSteps = r.getSteps(_stratStepsIndex);
        address[] memory _harvestSteps = r.getSteps(_harvestStepsIndex);
        address[] memory _oracleSteps = r.getSteps(_oracleStepsIndex);

        if (stratStepsLength > 0) {
            // console.log("stratStepsLength > 0");
            _harvestStrategy();
            _exitStrategy();
        }

        // console.log("setup strat steps");
        for (uint16 i = 0; i < _stratSteps.length; i++) {
            stratSteps[i] = _stratSteps[i];
            stratStepsParameters[i] = _stratStepsParameters[i];
        }
        stratStepsLength = uint16(_stratSteps.length);

        // console.log("setup harvest steps");
        for (uint16 i = 0; i < _harvestSteps.length; i++) {
            harvestSteps[i] = _harvestSteps[i];
            harvestStepsParameters[i] = _harvestStepsParameters[i];
        }
        harvestStepsLength = uint16(_harvestSteps.length);

        // console.log("setup oracle steps");
        for (uint16 i = 0; i < _oracleSteps.length; i++) {
            oracleSteps[i] = _oracleSteps[i];
            oracleStepsParameters[i] = _oracleStepsParameters[i];
        }
        oracleStepsLength = uint16(_oracleSteps.length);

        initialized = true;
    }

    function getStrat()
        external
        view
        returns (
            address[] memory _stratSteps,
            bytes[] memory _stratStepsParameters,
            address[] memory _harvestSteps,
            bytes[] memory _harvestStepsParameters,
            address[] memory _oracleSteps,
            bytes[] memory _oracleStepsParameters
        )
    {
        uint16 _stratStepsLength = stratStepsLength;
        uint16 _harvestStepsLength = harvestStepsLength;
        uint16 _oracleStepsLength = oracleStepsLength;

        _stratSteps = new address[](_stratStepsLength);
        _stratStepsParameters = new bytes[](_stratStepsLength);
        _harvestSteps = new address[](_harvestStepsLength);
        _harvestStepsParameters = new bytes[](_harvestStepsLength);
        _oracleSteps = new address[](_oracleStepsLength);
        _oracleStepsParameters = new bytes[](_oracleStepsLength);

        for (uint16 i = 0; i < _stratStepsLength; i++) {
            _stratSteps[i] = stratSteps[i];
            _stratStepsParameters[i] = stratStepsParameters[i];
        }

        for (uint16 i = 0; i < _harvestStepsLength; i++) {
            _harvestSteps[i] = harvestSteps[i];
            _harvestStepsParameters[i] = harvestStepsParameters[i];
        }

        for (uint16 i = 0; i < _oracleStepsLength; i++) {
            _oracleSteps[i] = oracleSteps[i];
            _oracleStepsParameters[i] = oracleStepsParameters[i];
        }
    }

    // function emergencyExitStrategy() external onlyOwner {
    //     _harvestStrategy();
    //     _exitStrategy();
    //     for (uint16 i = 0; i < stratStepsLength; i++) {
    //         stratSteps[i] = stratSteps[i];
    //     }
    //     _enterInStrategy();
    // }

    function _getNativeTVL() internal view returns (uint256) {
        console.log("___________________________");
        console.log("Entering in _getNativeTVL()");
        uint256 tvl = 0;
        address _asset = asset();

        IStratStep.OracleResponse memory _tmp;
        _tmp.vault = address(this);

        console.log("Chaining oracle response");

        if (oracleStepsLength == 0) {
            return IERC20(_asset).balanceOf(address(this));
        } else if (oracleStepsLength == 1) {
            console.log("Only one oracle step to check");
            _tmp = IStratStep(oracleSteps[0]).oracleExit(
                _tmp,
                oracleStepsParameters[0]
            );
        } else {
            uint16 revertedIndex = oracleStepsLength - 1;
            for (uint16 i = 0; i < oracleStepsLength; i++) {
                // console.log("Oracle response %s", revertedIndex - i);
                IStratStep.OracleResponse memory _before = _tmp;
                IStratStep.OracleResponse memory _after = IStratStep(
                    oracleSteps[revertedIndex - i]
                ).oracleExit(_before, oracleStepsParameters[revertedIndex - i]);
                _tmp = _after;
            }
        }

        console.log("Check native token oracle response");
        for (uint i = 0; i < _tmp.tokens.length; i++) {
            console.log("  - Token %s with %s amount", IERC20Metadata(_tmp.tokens[i]).name(), _tmp.tokensAmount[i]);

            if (_tmp.tokens[i] == _asset) {
                console.log("   Native token finded with %s amount", _tmp.tokensAmount[i]);
                tvl += _tmp.tokensAmount[i];
            }
        }

        tvl += IERC20(_asset).balanceOf(address(this));
        console.log("Final TVL with %s amount", tvl);
        console.log("___________________________");
        return tvl;
    }

    function totalAssets() public view virtual override returns (uint256) {
        return _getNativeTVL();
    }

    function _harvestStrategy() private {
        for (uint16 i = 0; i < harvestStepsLength; i++) {
            (bool success, ) = harvestSteps[i].delegatecall(
                abi.encodeWithSignature(
                    "enter(bytes)",
                    harvestStepsParameters[i]
                )
            );

            if (!success) {
                revert(
                    string.concat("Step err harvest: ", Strings.toString(i))
                );
            }
        }
    }

    function _enterInStrategy() private {
        console.log("enter in _enterInStrategy()");
        for (uint16 i = 0; i < stratStepsLength; i++) {
            (bool success, ) = stratSteps[i].delegatecall(
                abi.encodeWithSignature("enter(bytes)", stratStepsParameters[i])
            );

            if (!success) {
                revert(string.concat("Step err enter: ", Strings.toString(i)));
            }
        }
    }

    function _harvestFees() private {
        uint256 tAssets = totalAssets();
        // console.log("tAssets: ", tAssets);
        uint256 tSupply = totalSupply();
        // console.log("tSupply: ", tSupply);
        uint256 _lastFeeHarvestIndex = lastFeeHarvestIndex;
        // console.log("_lastFeeHarvestIndex: ", _lastFeeHarvestIndex);
        uint256 currentVaultIndex = (tAssets * 10000) / tSupply;
        // console.log("currentVaultIndex: ", currentVaultIndex);

        if (
            _lastFeeHarvestIndex == currentVaultIndex ||
            currentVaultIndex < _lastFeeHarvestIndex
        ) {
            lastFeeHarvestIndex = currentVaultIndex;
            return;
        }

        uint256 lastFeeHarvestIndexDiff = currentVaultIndex -
            _lastFeeHarvestIndex;
        // console.log("lastFeeHarvestIndexDiff: ", lastFeeHarvestIndexDiff);
        uint256 nativeTokenFees = (lastFeeHarvestIndexDiff *
            tSupply *
            performanceFees) / (100000000); //

        lastFeeHarvestIndex =
            currentVaultIndex -
            ((lastFeeHarvestIndexDiff * performanceFees) / 10000);
        // console.log("nativeTokenFees: ", nativeTokenFees);
        // console.log("_lastFeeHarvestIndex: ", _lastFeeHarvestIndex);
        IERC20(asset()).transfer(feeCollector, nativeTokenFees);
    }

    function _exitStrategy() private {
        if (stratStepsLength == 0) return;

        if (oracleStepsLength == 1) {
            console.log("Only one  step to check");
            (bool success, ) = stratSteps[0].delegatecall(
                abi.encodeWithSignature(
                    "exit(bytes)",
                    stratStepsParameters[0]
                )
            );
            console.log("success: %s", success);
            if (!success) {
                revert(string.concat("Step err exit: 0"));
            }

            return;
        } else {
            console.log("Many step to check");
            uint16 revertedIndex = stratStepsLength - 1;
            for (uint16 i = 0; i < stratStepsLength; i++) {
                console.log("Step %s: ", i);
                (bool success, ) = stratSteps[revertedIndex - i].delegatecall(
                    abi.encodeWithSignature(
                        "exit(bytes)",
                        stratStepsParameters[revertedIndex - i]
                    )
                );

                console.log("success: %s", success);
                if (!success) {
                    revert(string.concat("Step err exit: ", Strings.toString(i)));
                }
            }
        }
    }

    function harvest() external {
        _harvestStrategy();
        _exitStrategy();
        _harvestFees();
        _enterInStrategy();
    }

    /** @dev See {IERC4262-deposit}. */
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        returns (uint256)
    {
        require(initialized, '!initialized');
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more than max"
        );

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
        _enterInStrategy();

        return shares;
    }

    /** @dev See {IERC4262-mint}. */
    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        returns (uint256)
    {
        require(initialized, '!initialized');
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);
        _enterInStrategy();

        return assets;
    }

    /** @dev See {IERC4262-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(
            assets <= maxWithdraw(owner),
            "ERC4626: withdraw more than max"
        );

        // _harvestStrategy();
        _exitStrategy();
        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        if (totalAssets() > 0) _enterInStrategy();

        return shares;
    }

    /** @dev See {IERC4262-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        // _harvestStrategy();
        _exitStrategy();
        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        if (totalAssets() > 0) _enterInStrategy();

        return assets;
    }
}

