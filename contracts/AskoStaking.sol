pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./library/BasisPoints.sol";


contract AskoStaking is Initializable, Ownable {
    using BasisPoints for uint;
    using SafeMath for uint;

    uint256 constant internal DISTRIBUTION_MULTIPLIER = 2 ** 64;

    uint public stakingTaxBP;
    uint public unstakingTaxBP;
    IERC20 private askoToken;

    mapping(address => uint) public stakeValue;
    mapping(address => int) private stakerPayouts;

    uint public totalDistributions;
    uint public totalStaked;
    uint public totalStakers;
    uint private profitPerShare;
    uint private emptyStakeTokens; //These are tokens given to the contract when there are no stakers.

    event OnDistribute(uint amountSent);
    event OnStake(address sender, uint amount, uint tax);
    event OnUnstake(address sender, uint amount, uint tax);

    modifier onlyAskoToken {
        require(msg.sender == address(askoToken), "Can only be called by AskoToken contract.");
        _;
    }

    function initialize(uint _stakingTaxBP, uint _ustakingTaxBP, address owner, IERC20 _askoToken) public initializer {
        Ownable.initialize(msg.sender);
        stakingTaxBP = _stakingTaxBP;
        unstakingTaxBP = _ustakingTaxBP;
        askoToken = _askoToken;
        //Due to issue in oz testing suite, the msg.sender might not be owner
        _transferOwnership(owner);
    }

    function stake(uint amount) public {
        require(amount >= 1e18, "Must stake at least one ASKO.");
        require(askoToken.balanceOf(msg.sender) >= amount, "Cannot stake more ASKO than you hold unstaked.");
        uint tax = findTaxAmount(amount, stakingTaxBP);
        uint stakeAmount = amount.sub(tax);
        totalStakers = totalStakers.add(1);
        totalStaked = totalStaked.add(stakeAmount);
        stakeValue[msg.sender] = stakeValue[msg.sender].add(stakeAmount);
        uint payout = profitPerShare.mul(stakeAmount);
        stakerPayouts[msg.sender] = stakerPayouts[msg.sender] + uintToInt(payout);
        _increaseProfitPerShare(tax);
        require(askoToken.transferFrom(msg.sender, address(this), amount), "Stake failed due to failed transfer.");
        emit OnStake(msg.sender, amount, tax);
    }

    function unstake(uint amount) public {
        require(amount >= 1e18, "Must unstake at least one ASKO.");
        require(stakeValue[msg.sender] >= amount, "Cannot unstake more ASKO than you have staked.");
        uint tax = findTaxAmount(amount, unstakingTaxBP);
        uint earnings = amount.sub(tax);
        if (stakeValue[msg.sender] == amount) totalStakers = totalStakers.sub(1);
        totalStaked = totalStaked.sub(amount);
        stakeValue[msg.sender] = stakeValue[msg.sender].sub(amount);
        _increaseProfitPerShare(tax);
        require(askoToken.transferFrom(address(this), msg.sender, earnings), "Unstake failed due to failed transfer.");
        emit OnUnstake(msg.sender, amount, tax);
    }

    function withdraw(uint amount) public {
        require(dividendsOf(msg.sender) >= uintToInt(amount), "Cannot withdraw more dividends than you have earned.");
        stakerPayouts[msg.sender] = stakerPayouts[msg.sender] + uintToInt(amount);
        askoToken.transfer(msg.sender, amount);
    }

    function distribute(uint amount) public {
        require(askoToken.balanceOf(msg.sender) >= amount, "Cannot distribute more ASKO than you hold unstaked.");
        totalDistributions = totalDistributions.add(amount);
        _increaseProfitPerShare(amount);
        require(
            askoToken.transferFrom(msg.sender, address(this), amount),
            "Distribution failed due to failed transfer."
        );
        emit OnDistribute(amount);
    }

    function handleTaxDistribution(uint amount) public onlyAskoToken {
        totalDistributions = totalDistribution.add(amount);
        _increaseProfitPerShare(amount);
        emit OnDistribute(amount);
    }

    function dividendsOf(address staker) public view returns (int) {
        return (uintToInt(profitPerShare.mul(stakeValue[staker]))-(stakerPayouts[staker])) /
                uintToInt(DISTRIBUTION_MULTIPLIER);
    }

    function findTaxAmount(uint value, uint taxBP) public pure returns (uint) {
        return value.mulBP(taxBP);
    }

    function uintToInt(uint val) internal pure returns (int) {
        if (val >= uint(-1).div(2)) {
            require(false, "Overflow. Cannot convert uint to int.");
        } else {
            return int(val);
        }
    }

    function _increaseProfitPerShare(uint amount) internal {
        if (totalStaked != 0) {
            if (emptyStakeTokens != 0) {
                amount = amount.add(emptyStakeTokens);
                emptyStakeTokens = 0;
            }
            profitPerShare = profitPerShare.add(amount.mul(DISTRIBUTION_MULTIPLIER).div(totalStaked));
        } else {
            emptyStakeTokens = emptyStakeTokens.add(amount);
        }
    }

}
