// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ERC20} from "./ERC20.sol";
import {ReentrancyGuard} from "./lib_ReentrancyGuard.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {EnumerableMap} from "./EnumerableMap.sol";

contract PirexFeesContributors is ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint256 public constant FEE_PERCENT_DENOMINATOR = 250_000;

    address payable public immutable pirexCoreMultisig;

    // Visibility cannot be public due to nested structs
    EnumerableMap.AddressToUintMap private _contributors;

    event UpdateContributorAddress(
        address indexed oldContributor,
        address indexed newContributor
    );
    event Distribute(
        ERC20[] tokens,
        uint256[] tokenBalances,
        address[] contributors,
        uint256[] feePercents,
        uint256[][] distributionAmounts
    );
    event DistributeETH(
        uint256 totalETH,
        address[] contributors,
        uint256[] feePercents,
        uint256[] distributionAmounts
    );
    event ETHDistributionFailure(
        address indexed contributor,
        uint256 feePercent,
        uint256 ethAmount
    );

    error EmptyArray();
    error MismatchedArrays();
    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized();
    error ExistingContributor();

    receive() external payable {}

    /**
     * @param  _pirexCoreMultisig  address    Pirex Core multisig
     * @param  contributors        address[]  Contributor addresses
     * @param  feePercents         uint256[]  Contributor fee percents
     */
    constructor(
        address _pirexCoreMultisig,
        address[] memory contributors,
        uint256[] memory feePercents
    ) {
        if (_pirexCoreMultisig == address(0)) revert ZeroAddress();

        pirexCoreMultisig = payable(_pirexCoreMultisig);

        uint256 cLen = contributors.length;

        if (cLen == 0) revert EmptyArray();
        if (feePercents.length == 0) revert EmptyArray();
        if (cLen != feePercents.length) revert MismatchedArrays();

        uint256 totalFeePercent;

        for (uint256 i; i < cLen; ) {
            address contributor = contributors[i];
            uint256 feePercent = feePercents[i];

            if (contributor == address(0)) revert ZeroAddress();
            if (feePercent == 0) revert ZeroAmount();

            totalFeePercent += feePercent;

            _contributors.set(contributor, feePercent);

            unchecked {
                ++i;
            }
        }

        // Total must add up to the denominator, otherwise there will be undistributed fees
        assert(totalFeePercent == FEE_PERCENT_DENOMINATOR);
    }

    // Restricts certain methods to being called only by a contributor
    modifier onlyContributor() {
        if (_contributors.contains(msg.sender) == false) revert Unauthorized();
        _;
    }

    /**
     * @notice Get contributor addresses and fee percents
     * @return contributors  address[]  Contributor addresses
     * @return feePercents   uint256[]  Contributor fee percents
     */
    function getAll()
        public
        view
        returns (address[] memory contributors, uint256[] memory feePercents)
    {
        uint256 len = _contributors.length();
        contributors = new address[](len);
        feePercents = new uint256[](len);

        for (uint256 i; i < len; ) {
            (address contributor, uint256 feePercent) = _contributors.at(i);
            contributors[i] = contributor;
            feePercents[i] = feePercent;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Get a contributor's fee percent
     * @param  contributor  address  Contributor address
     * @return              uint256  Contributor fee percent
     */
    function get(address contributor) external view returns (uint256) {
        return _contributors.get(contributor);
    }

    /**
     * @notice Update a contributor's address (only callable by the contributor)
     * @param  contributor  address  Contributor address
     */
    function updateContributorAddress(address contributor)
        external
        onlyContributor
    {
        if (contributor == address(0)) revert ZeroAddress();

        // Cannot use the address of an existing contributor
        if (_contributors.contains(contributor)) revert ExistingContributor();

        // Maintain the same fee percent for the contributor
        uint256 feePercent = _contributors.get(msg.sender);

        // Remove msg.sender from the list of contributors
        assert(_contributors.remove(msg.sender));

        // Add the new contributor with the previous percent
        assert(_contributors.set(contributor, feePercent));

        emit UpdateContributorAddress(msg.sender, contributor);
    }

    /**
     * @notice Distribute contributor fees
     * @param  tokens  ERC20[]  Tokens which will be distributed
     */
    function distribute(ERC20[] memory tokens)
        external
        nonReentrant
        onlyContributor
    {
        uint256 tLen = tokens.length;

        if (tLen == 0) revert EmptyArray();

        uint256[] memory tokenBalances = new uint256[](tLen);
        (
            address[] memory contributors,
            uint256[] memory feePercents
        ) = getAll();
        uint256 cLen = contributors.length;
        uint256[][] memory distributionAmounts = new uint256[][](tLen);

        // Iterate over token addresses and distribute fees to each contributor
        for (uint256 i; i < tLen; ++i) {
            ERC20 token = tokens[i];
            uint256 tokenBalance = token.balanceOf(address(this));
            tokenBalances[i] = tokenBalance;
            distributionAmounts[i] = new uint256[](cLen);

            // Skip distribution for this token as the balance is too small
            if ((tokenBalance / FEE_PERCENT_DENOMINATOR) == 0) continue;

            for (uint256 j; j < cLen; ++j) {
                bool isLast = j == (cLen - 1);

                // If this is the *last* contributor set the transfer amount to the token balance
                // to account for Solidity decimal truncation
                uint256 amount = isLast
                    ? token.balanceOf(address(this))
                    : tokenBalance.mulDivDown(
                        feePercents[j],
                        FEE_PERCENT_DENOMINATOR
                    );

                distributionAmounts[i][j] = amount;

                token.safeTransfer(contributors[j], amount);
            }
        }

        emit Distribute(
            tokens,
            tokenBalances,
            contributors,
            feePercents,
            distributionAmounts
        );
    }

    /**
     * @notice Distribute contributor fees (ETH only)
     */
    function distributeETH() external nonReentrant onlyContributor {
        uint256 totalETH = address(this).balance;

        // Ensure that contract's ETH balance is sufficient to avoid distributing zero amounts
        // the minimum amount needed is 0.00000000000025 ETH
        if ((totalETH / FEE_PERCENT_DENOMINATOR) == 0) revert ZeroAmount();

        (
            address[] memory contributors,
            uint256[] memory feePercents
        ) = getAll();
        uint256 cLen = contributors.length;
        uint256[] memory distributionAmounts = new uint256[](cLen);

        // Distribute ETH fees to each contributor
        for (uint256 i; i < cLen; ++i) {
            bool isLast = i == (cLen - 1);

            // If this is the *last* contributor set the transfer amount to the balance
            // to account for Solidity decimal truncation
            uint256 amount = isLast
                ? address(this).balance
                : totalETH.mulDivDown(feePercents[i], FEE_PERCENT_DENOMINATOR);

            distributionAmounts[i] = amount;

            // Normally, we'd revert if the returned boolean value were false, but it is the responsibility
            // of the contributor to set an address that can receive ETH (i.e. not a contract w/o a receive function)
            (bool sent, ) = payable(contributors[i]).call{value: amount}("");

            // Emit the ETHDistributionFailure event so that it can be handled
            if (!sent) {
                // Transfer the failed tranfer amount to the multisig where it can be evaluated and handled manually
                (bool sentFallback, ) = pirexCoreMultisig.call{value: amount}(
                    ""
                );

                // The multisig implementation has the fallback function implemented and can receive ETH
                // https://arbiscan.io/address/0x3e5c63644e683549055b9be8653de26e0b4cd36e#code#F2#L27
                // https://arbiscan.io/address/0x3e5c63644e683549055b9be8653de26e0b4cd36e#code#F5#L1
                assert(sentFallback);

                emit ETHDistributionFailure(
                    contributors[i],
                    feePercents[i],
                    amount
                );
            }
        }

        emit DistributeETH(
            totalETH,
            contributors,
            feePercents,
            distributionAmounts
        );
    }
}

