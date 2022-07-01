const { expect } = require("chai")
const { ethers } = require("hardhat")
const privateKey = require("./privateKey")
const getSignature = require("../libs/signer")

describe("Escrow", () => {
    before(async () => {
        const users = await ethers.getSigners()
        this.users = users
        const [owner, feeReceiver, alice] = users
        this.owner = owner
        this.alice = alice
        this.feeReceiver = feeReceiver

        const Escrow = await ethers.getContractFactory("Escrow")
        const PrizeToken1 = await ethers.getContractFactory("PrizeToken1")
        const PrizeToken2 = await ethers.getContractFactory("PrizeToken2")
        const PrizeToken3 = await ethers.getContractFactory("PrizeToken3")

        this.escrow = await Escrow.deploy(feeReceiver.address, 2)
        this.PrizeToken1 = await PrizeToken1.deploy(this.alice.address)
        this.PrizeToken2 = await PrizeToken2.deploy(this.alice.address)
        this.PrizeToken3 = await PrizeToken3.deploy(this.alice.address)

        this.PrizeToken1.connect(this.alice).approve(this.escrow.address, 10000)
        this.PrizeToken2.connect(this.alice).approve(this.escrow.address, 10000)
        this.PrizeToken3.connect(this.alice).approve(this.escrow.address, 10000)

        this.aliceSingature = getSignature(privateKey(2), [
            [
                { tokenAddress: this.PrizeToken1.address, tokenAmount: 10 },
                { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 5 }, // Eth
                { tokenAddress: this.PrizeToken2.address, tokenAmount: 2 },
            ],
            [
                { tokenAddress: this.PrizeToken1.address, tokenAmount: 5 },
                { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 2 },
                { tokenAddress: this.PrizeToken3.address, tokenAmount: 3 },
            ],
            [
                { tokenAddress: this.PrizeToken1.address, tokenAmount: 2 },
                { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 2 },
            ],
        ])
    })

    describe("Send ETh to the contract", () => {
        it("Sending Ether fails: Not enough Eth", async () => {
            await expect(
                this.escrow.connect(this.alice).sendETHToContract(this.aliceSingature, { value: 1 }),
            ).to.revertedWith("EscrowError(0)")
        })

        it("Sending Ether succeeds", async () => {
            await expect(this.escrow.connect(this.alice).sendETHToContract(this.aliceSingature, { value: 11 }))
                .to.emit(this.escrow, "ETHSent")
                .withArgs(11)
        })
    })

    describe("Create cotest", () => {
        it("Creating contest fails: TotalETH is not the same as quiz builder deposited", async () => {
            await expect(
                this.escrow.connect(this.owner).createContest(this.aliceSingature, [
                    [
                        { tokenAddress: this.PrizeToken1.address, tokenAmount: 10 },
                        { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 5 },
                        { tokenAddress: this.PrizeToken2.address, tokenAmount: 2 },
                    ],
                    [
                        { tokenAddress: this.PrizeToken1.address, tokenAmount: 5 },
                        { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 2 },
                        { tokenAddress: this.PrizeToken3.address, tokenAmount: 3 },
                    ],
                    [
                        { tokenAddress: this.PrizeToken1.address, tokenAmount: 2 },
                        { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 3 },
                    ],
                ]),
            ).to.revertedWith("EscrowError(0)")
        })

        it("Creating contest succeeds", async () => {
            await expect(
                this.escrow.connect(this.owner).createContest(this.aliceSingature, [
                    [
                        { tokenAddress: this.PrizeToken1.address, tokenAmount: 10 },
                        { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 5 },
                        { tokenAddress: this.PrizeToken2.address, tokenAmount: 2 },
                    ],
                    [
                        { tokenAddress: this.PrizeToken1.address, tokenAmount: 5 },
                        { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 2 },
                        { tokenAddress: this.PrizeToken3.address, tokenAmount: 3 },
                    ],
                    [
                        { tokenAddress: this.PrizeToken1.address, tokenAmount: 2 },
                        { tokenAddress: "0x0000000000000000000000000000000000000000", tokenAmount: 2 },
                    ],
                ]),
            )
                .to.emit(this.escrow, "ContestCreated")
                .withArgs(this.alice.address, 3, 1)
            // check token is transferred to recipient
            expect((await this.PrizeToken1.balanceOf(this.escrow.address)).toNumber()).to.equal(17)
            expect((await this.PrizeToken2.balanceOf(this.escrow.address)).toNumber()).to.equal(2)
            expect((await this.PrizeToken3.balanceOf(this.escrow.address)).toNumber()).to.equal(3)
        })
    })

    describe("End cotest", () => {
        it("Ending contest fails: Caller is not the owner", async () => {
            const [, , , , , bob, cathy, daniel] = this.users // Winners
            await expect(
                this.escrow.connect(this.alice).endContest(1, [bob.address, cathy.address, daniel.address]),
            ).to.revertedWith("Ownable: caller is not the owner")
        })

        it("Ending contest fails: Winners are not correct", async () => {
            const [, , , , , bob, cathy] = this.users // Winners
            await expect(this.escrow.connect(this.owner).endContest(1, [bob.address, cathy.address])).to.revertedWith(
                "EscrowError(2)",
            )
        })

        it("Ending contest succeeds", async () => {
            const [, , , , , bob, cathy, daniel] = this.users // Winners

            await this.escrow.connect(this.owner).endContest(1, [bob.address, cathy.address, daniel.address])

            expect((await this.PrizeToken1.balanceOf(bob.address)).toNumber()).to.equal(10)
            expect((await this.PrizeToken2.balanceOf(bob.address)).toNumber()).to.equal(2)
            expect((await this.PrizeToken3.balanceOf(bob.address)).toNumber()).to.equal(0)

            expect((await this.PrizeToken1.balanceOf(cathy.address)).toNumber()).to.equal(5)
            expect((await this.PrizeToken2.balanceOf(cathy.address)).toNumber()).to.equal(0)
            expect((await this.PrizeToken3.balanceOf(cathy.address)).toNumber()).to.equal(3)

            expect((await this.PrizeToken1.balanceOf(daniel.address)).toNumber()).to.equal(2)
            expect((await this.PrizeToken2.balanceOf(daniel.address)).toNumber()).to.equal(0)
            expect((await this.PrizeToken3.balanceOf(daniel.address)).toNumber()).to.equal(0)
        })

        it("Ending contest fails: Already finished", async () => {
            const [, , , , , bob, cathy, daniel] = this.users // Winners
            await expect(
                this.escrow.connect(this.owner).endContest(1, [bob.address, cathy.address, daniel.address]),
            ).to.revertedWith("EscrowError(1)")
        })
    })
})
