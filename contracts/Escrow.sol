// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Escrow is Ownable, ReentrancyGuard {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeERC20 for IERC20;

    /// -----------------------------------------------------------------------
    /// Struct
    /// -----------------------------------------------------------------------

    /// @param tokenAddress Prize token address
    /// @param tokenAmount Token amount
    struct Token {
        address tokenAddress;
        uint256 tokenAmount;
    }

    /// @param contestId Contest id
    /// @param contestOwner Quiz builder address
    /// @param prize Prize token info
    /// @param prizeCountPerRank Number of prize tokens per winner
    /// @param finished Bool variable if contest is finished or not
    struct ContestInfo {
        uint256 contestId;
        address contestOwner;
        mapping(uint256 => mapping(uint256 => Token)) prize;
        uint256[] prizeCountPerRank;
        bool finished;
    }

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    enum EscrowErrorCodes {
        INSUFFICIENT_BALANCE,
        CONTEST_ALREADY_FINISHED,
        WINNERS_NOT_CORRECT,
        FAILED_TO_SEND_ETH,
        FEE_NOT_PAID
    }

    error EscrowError(EscrowErrorCodes code);

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @dev Emits when quiz builder creates the contest.
    /// @param builder Quiz builder address
    /// @param winnersCount Number of winners
    /// @param contestId Created contest id
    event ContestCreated(address indexed builder, uint256 winnersCount, uint256 contestId);

    /// @dev Emits when contest ended.
    /// @param contestId Ended contest id
    /// @param contestOwner Address of contest owner
    /// @param winners Array of winner addresses
    /// @param winnersCount Number of winners
    event ContestEnded(uint256 contestId, address contestOwner, address[] winners, uint256 winnersCount);

    /// @dev Emits when owner withdrew all of eth in contract.
    /// @param feeReceiver Address of fee receiver
    /// @param balance Total balance of eth in contract
    event ETHWithdrew(address indexed feeReceiver, uint256 balance);

    /// @dev Emits when owner withdrew all of given ERC20 token in contract.
    /// @param feeReceiver Address of fee receiver
    /// @param tokenAddress ERC20 token address
    /// @param balance Total balance of given token in contract
    event ERC20TokenWithdrew(address indexed feeReceiver, address tokenAddress, uint256 balance);

    /// @dev Emits when owner updated the address of fee receiver.
    /// @param previousReceiver Address of previous fee receiver
    /// @param newReceiver Address of new fee receiver
    event FeeReceiverUpdated(address indexed previousReceiver, address indexed newReceiver);

    /// @dev Emits when protocol fee updated.
    /// @param previousFee Previous protocol fee
    /// @param newFee New protocol fee
    event ProtocolFeeUpdated(uint256 previousFee, uint256 newFee);

    /// @dev Emits when quiz builder sent eth to the contract
    /// @param totalETH Total ETH amount quiz builder sent
    event ETHSent(uint256 totalETH);

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Fee receiver address
    address public feeReceiver;

    /// @notice Protocol fee
    uint256 public protocolFee;

    /// @notice Current contest Id
    uint256 public currentContest;

    /// @notice Mapping of contests
    mapping(uint256 => ContestInfo) public contests;

    /// @notice Mapping of ETH by signature
    mapping(bytes => uint256) public ETHSig;

    /// @notice Quiz builder paid fee or not
    mapping(bytes => bool) public feePaid;

    /* ===== INIT ===== */

    /// @dev Constructor
    /// @param _feeReceiver Fee receiver address
    /// @param _protocolFee Protocol fee
    constructor(address _feeReceiver, uint256 _protocolFee) {
        feeReceiver = _feeReceiver;
        protocolFee = _protocolFee;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    /// -----------------------------------------------------------------------
    /// Quiz builder actions
    /// -----------------------------------------------------------------------

    /// @dev Send ETH to the contract.
    /// @dev Quiz builder should call this method by paying gas at least if they are going to set ETH for prize token.
    /// @param _signature Quiz builder's signed message from off chain
    function sendETHToContract(bytes calldata _signature) external payable {
        if (msg.value < protocolFee) revert EscrowError(EscrowErrorCodes.INSUFFICIENT_BALANCE);
        ETHSig[_signature] = msg.value - protocolFee;
        feePaid[_signature] = true;

        emit ETHSent(msg.value);
    }

    /// @dev Create contest with quiz builder's signature and prize token info.
    /// @dev Manager should call this method for creating contest instead of quiz builder so that pay gas for them.
    /// @dev If the prize token is native token, its token address should be 0.
    /// @dev Signature has to be hash with its private key and data
    /// @param _signature Quiz builder's signed message from off chain
    /// @param _prize Array of prize for winners
    function createContest(bytes memory _signature, Token[][] calldata _prize) external nonReentrant onlyOwner {
        uint256 i;
        uint256 j;
        uint256 totalEth;
        bytes memory signature;

        if (feePaid[_signature] == false) revert EscrowError(EscrowErrorCodes.FEE_NOT_PAID);

        for (i = 0; i < _prize.length; i++) {
            for (j = 0; j < _prize[i].length; j++) {
                if (_prize[i][j].tokenAddress == address(0)) {
                    totalEth += _prize[i][j].tokenAmount;
                }
                signature = abi.encodePacked(signature, _prize[i][j].tokenAddress, _prize[i][j].tokenAmount);
            }
        }

        if (totalEth != ETHSig[_signature]) revert EscrowError(EscrowErrorCodes.INSUFFICIENT_BALANCE);

        bytes32 message = keccak256(signature);
        address contestOwner = ECDSA.recover(ECDSA.toEthSignedMessageHash(message), _signature);

        currentContest++;
        ContestInfo storage contest = contests[currentContest];
        contest.contestId = currentContest;
        contest.contestOwner = contestOwner;

        for (i = 0; i < _prize.length; i++) {
            contest.prizeCountPerRank.push(_prize[i].length);
            for (j = 0; j < _prize[i].length; j++) {
                contest.prize[i][j] = _prize[i][j];
                if (_prize[i][j].tokenAddress != address(0)) {
                    IERC20(_prize[i][j].tokenAddress).safeTransferFrom(
                        contestOwner,
                        address(this),
                        _prize[i][j].tokenAmount
                    );
                }
            }
        }

        emit ContestCreated(contestOwner, _prize.length, currentContest);
    }

    /// -----------------------------------------------------------------------
    /// Owner actions
    /// -----------------------------------------------------------------------

    /// @dev End the contest and distribute the prize to the winners.
    /// @dev Array of winners and prize layout should be the same.
    /// @dev Only owner can end this contest.
    /// @param _contestId Contest id to end
    /// @param _winners Array of winner address
    function endContest(uint256 _contestId, address[] memory _winners) external onlyOwner {
        ContestInfo storage contest = contests[_contestId];

        if (contest.finished == true) revert EscrowError(EscrowErrorCodes.CONTEST_ALREADY_FINISHED);

        if (_winners.length != contest.prizeCountPerRank.length)
            revert EscrowError(EscrowErrorCodes.WINNERS_NOT_CORRECT);

        contest.finished = true;

        for (uint256 i = 0; i < contest.prizeCountPerRank.length; i++) {
            for (uint256 j = 0; j < contest.prizeCountPerRank[i]; j++) {
                if (contest.prize[i][j].tokenAddress == address(0)) {
                    (bool success, ) = payable(_winners[i]).call{ value: contest.prize[i][j].tokenAmount }("");
                    if (success == false) revert EscrowError(EscrowErrorCodes.FAILED_TO_SEND_ETH);
                } else {
                    IERC20(contest.prize[i][j].tokenAddress).safeTransfer(_winners[i], contest.prize[i][j].tokenAmount);
                }
            }
        }

        emit ContestEnded(_contestId, contest.contestOwner, _winners, _winners.length);
    }

    /// @dev Withdraw all ETH in contract to the fee receiver.
    function withdrawETH() external onlyOwner {
        (bool success, ) = payable(feeReceiver).call{ value: address(this).balance }("");
        if (success == false) revert EscrowError(EscrowErrorCodes.FAILED_TO_SEND_ETH);

        emit ETHWithdrew(feeReceiver, address(this).balance);
    }

    /// @dev Withdraw all given ERC20 token in contract to the fee receiver.
    /// @param _tokenAddress Token address
    function withdrawERC20Token(address _tokenAddress) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(feeReceiver, IERC20(_tokenAddress).balanceOf(address(this)));

        emit ERC20TokenWithdrew(feeReceiver, _tokenAddress, IERC20(_tokenAddress).balanceOf(address(this)));
    }

    /// @dev Set new fee receiver address.
    /// @param _newReceiver New fee receiver address
    function updateFeeReceiver(address _newReceiver) external onlyOwner {
        emit FeeReceiverUpdated(feeReceiver, _newReceiver);

        feeReceiver = _newReceiver;
    }

    /// @dev Set new fee protocol fee.
    /// @param _newFee New protocol fee
    function updateProtocolFee(uint256 _newFee) external onlyOwner {
        emit ProtocolFeeUpdated(protocolFee, _newFee);

        protocolFee = _newFee;
    }
}
