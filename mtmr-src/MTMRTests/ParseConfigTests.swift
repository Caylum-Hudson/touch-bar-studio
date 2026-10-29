import XCTest

class ParseConfig: XCTestCase {
    func testPomodoroStateRestoresAcrossItemRecreationAndSleep() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let state = PomodoroBarItem.TimerState(phase: .work, deadline: start.addingTimeInterval(1_500))
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(PomodoroBarItem.TimerState.self, from: data)

        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.remainingSeconds(now: start.addingTimeInterval(1_497.2)), 3)
        XCTAssertTrue(restored.hasFinished(now: start.addingTimeInterval(1_500)))
    }

    func testPomodoroCompletionBoundaryIsStableAfterExpiry() {
        let state = PomodoroBarItem.TimerState(phase: .rest, deadline: Date(timeIntervalSince1970: 20_000))
        let afterExpiry = Date(timeIntervalSince1970: 20_001)

        XCTAssertTrue(state.hasFinished(now: afterExpiry))
        XCTAssertEqual(state.remainingSeconds(now: afterExpiry), 0)
        XCTAssertFalse(state.hasFinished(now: Date(timeIntervalSince1970: 19_999)))
    }

    func testButtonNoAction() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard result?.first?.actions.count == 0 else {
            XCTFail()
            return
        }
    }

    func testButtonKeyCodeAction() {
        let buttonKeycodeFixture = """
            [  { "type": "staticButton",  "title": "Pew", "actions": [ { "trigger": "singleTap", "action": "hidKey", "keycode": 123 } ] } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .hidKey(keycode: 123)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
    }
    
    func testButtonKeyCodeLegacyAction() {
        let buttonKeycodeFixture = """
            [  { "type": "staticButton",  "title": "Pew", "action": "hidKey", "keycode": 123 } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .hidKey(keycode: 123)? = result?.first?.legacyAction else {
            XCTFail()
            return
        }
    }

    func testPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("esc")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .keyPress(keycode: 53)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
    }

    func testExtendedWidthForPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape", "width": 110}, ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("esc")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .keyPress(keycode: 53)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
        guard case .width(110)? = result?.first?.additionalParameters[.width] else {
            XCTFail()
            return
        }
    }

    func testResolveColorDialDefaultsAndOptionsDecode() {
        let defaults = #"[{"type":"resolveColorDial"}]"#.data(using:.utf8)!
        let explicit = #"[{"type":"resolveColorDial","parameter":"gamma","channel":"R","width":90}]"#.data(using:.utf8)!
        guard case .resolveColorDial(parameter:"lift",channel:"Y",sensitivity:"fine")? = (try? JSONDecoder().decode([BarItemDefinition].self,from:defaults))?.first?.type else {
            XCTFail("Resolve color dial should default to Lift Y")
            return
        }
        guard case .resolveColorDial(parameter:"gamma",channel:"R",sensitivity:"fine")? = (try? JSONDecoder().decode([BarItemDefinition].self,from:explicit))?.first?.type else {
            XCTFail("Resolve color dial options should survive configuration decoding")
            return
        }
    }

    func testResolveColorDialReleaseAndTextBounds() {
        XCTAssertTrue(ResolveColorDialReleasePolicy.shouldWaitForWrite(pendingRawStep:1,writeScheduled:false))
        XCTAssertTrue(ResolveColorDialReleasePolicy.shouldWaitForWrite(pendingRawStep:0,writeScheduled:true))
        XCTAssertFalse(ResolveColorDialReleasePolicy.shouldWaitForWrite(pendingRawStep:0,writeScheduled:false))
        XCTAssertEqual(ResolveDialTextLayout.availableWidth(viewWidth:90,leadingX:30),56)
        XCTAssertEqual(ResolveDialTextLayout.availableWidth(viewWidth:110,leadingX:30),76)
        XCTAssertEqual(ResolveDialTextLayout.availableWidth(viewWidth:90,leadingX:30,trailingInset:100),0)
    }

    func testResolveColorDialStructureFailsClosed() {
        let sliders = (0..<4).map { index in ResolveColorSliderSnapshot(minimum:-1,maximum:1,value:Double(index) / 10,settable:true,displayValue:String(index)) }
        let groups = ["Lift","Gamma","Gain"].map { ResolveColorBarGroupSnapshot(heading:$0,sliders:sliders,sliderChildIndices:Array(0..<4)) }
        let valid = ResolveColorBarStructureSnapshot(selectedTabs:["ColorBars"],unrelatedSelectedTabs:["ColorWheels"],primariesGroupCount:1,groups:groups)
        XCTAssertEqual(ResolveColorDialStructure.slider(in:valid,parameter:.gamma,channel:.green)?.value,0.2)
        XCTAssertEqual(ResolveColorDialStructure.slider(in:valid,parameter:.gamma,channel:.green)?.displayValue,"2")
        let wrongTab = ResolveColorBarStructureSnapshot(selectedTabs:["ColorWheels"],primariesGroupCount:1,groups:groups)
        XCTAssertNil(ResolveColorDialStructure.slider(in:wrongTab,parameter:.gamma,channel:.green))
        let ambiguousPanel = ResolveColorBarStructureSnapshot(selectedTabs:["ColorBars"],primariesGroupCount:2,groups:groups)
        XCTAssertNil(ResolveColorDialStructure.slider(in:ambiguousPanel,parameter:.gamma,channel:.green))
        let readOnly = ResolveColorBarStructureSnapshot(selectedTabs:["ColorBars"],primariesGroupCount:1,groups:[ResolveColorBarGroupSnapshot(heading:"Lift",sliders:sliders.map { ResolveColorSliderSnapshot(minimum:$0.minimum,maximum:$0.maximum,value:$0.value,settable:false,displayValue:$0.displayValue) },sliderChildIndices:Array(0..<4))] + groups.dropFirst())
        XCTAssertNil(ResolveColorDialStructure.slider(in:readOnly,parameter:.lift,channel:.y))
        let gammaSiblings = [(role:"AXStaticText",label:"0.11 0.22 0.33 0.44"),(role:"AXCheckBox",label:"Pick White Point")]
        XCTAssertEqual(ResolveColorDialStructure.gammaDisplayLabel(from:gammaSiblings),"0.11 0.22 0.33 0.44")
        XCTAssertNil(ResolveColorDialStructure.gammaDisplayLabel(from:gammaSiblings + [(role:"AXStaticText",label:"1 2 3 4")]),"Ambiguous group values must not be shown as a grade readout")
    }

    func testResolveTimelineJogParserAndBoundedSensitivity() {
        let defaults = #"[{"type":"resolveTimelineJog"}]"#.data(using:.utf8)!
        guard case .resolveTimelineJog(sensitivity:"fine")? = (try? JSONDecoder().decode([BarItemDefinition].self,from:defaults))?.first?.type else {
            XCTFail("Timeline jog should default to fine sensitivity")
            return
        }
        let fixture = #"[{"type":"resolveTimelineJog","sensitivity":"coarse","width":90}]"#.data(using:.utf8)!
        guard case .resolveTimelineJog(sensitivity:"coarse")? = (try? JSONDecoder().decode([BarItemDefinition].self,from:fixture))?.first?.type else {
            XCTFail("Timeline jog sensitivity should decode")
            return
        }
        var accumulator = ResolveTimelineJogAccumulator()
        XCTAssertEqual(accumulator.advance(points:7.5,sensitivity:.normal),1)
        XCTAssertEqual(accumulator.advance(points:2.5,sensitivity:.normal),1)
        XCTAssertEqual(accumulator.advance(points:100,sensitivity:.coarse),ResolveTimelineJogAccumulator.maximumFramesPerUpdate)
        XCTAssertEqual(accumulator.advance(points:0,sensitivity:.fine),0,"Clamped overflow is discarded rather than queued")
        XCTAssertEqual(accumulator.advance(points:Double.greatestFiniteMagnitude,sensitivity:.coarse),ResolveTimelineJogAccumulator.maximumFramesPerUpdate)
        accumulator.reset()
        XCTAssertEqual(accumulator.advance(points:-50,sensitivity:.fine),-4)
    }

    func testResolveTimelineMenuDispatchTargetsOnlyTheEnabledLeaf() {
        func menu(_ role:String,_ title:String,enabled:Bool = true,children:[ResolveMenuNodeSnapshot] = []) -> ResolveMenuNodeSnapshot {
            ResolveMenuNodeSnapshot(role:role,title:title,enabled:enabled,children:children)
        }
        let workspace = menu("AXMenuBarItem","Workspace",children:[menu("AXMenu","",children:[menu("AXMenuItem","Active Panel Selection",children:[menu("AXMenu","",children:[menu("AXMenuItem","Timeline")])])])])
        let playback = menu("AXMenuBarItem","Playback",children:[menu("AXMenu","",children:[menu("AXMenuItem","Step One",children:[menu("AXMenu","",children:[menu("AXMenuItem","Frame Reverse"),menu("AXMenuItem","Frame Forward")])])])])
        let root = menu("AXMenuBar","",children:[workspace,playback])
        let focusTargets = ResolveTimelineMenuPath.pressTargets(in:root,titles:["Workspace","Active Panel Selection","Timeline"])
        XCTAssertEqual(focusTargets.map(\.title),["Timeline"],"Selecting the panel emits one AXPress at the leaf and none on menu ancestors")
        let stepTargets = ResolveTimelineMenuPath.pressTargets(in:root,titles:["Playback","Step One","Frame Reverse"])
        XCTAssertEqual(stepTargets.map(\.title),["Frame Reverse"])
        XCTAssertEqual(stepTargets.count,1)
        let ambiguous = menu("AXMenuBar","",children:[workspace,menu("AXMenuBarItem","Playback",children:[menu("AXMenu","",children:[menu("AXMenuItem","Step One",children:[menu("AXMenu","",children:[menu("AXMenuItem","Frame Reverse"),menu("AXMenuItem","Frame Reverse")])])])])])
        XCTAssertTrue(ResolveTimelineMenuPath.pressTargets(in:ambiguous,titles:["Playback","Step One","Frame Reverse"]).isEmpty)
    }
}
