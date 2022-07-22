// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Fuzzilli

let Seconds = 1.0
let Minutes = 60.0 * Seconds
let Hours   = 60.0 * Minutes

// A very basic terminal UI.
class TerminalUI {
    // If set, the next program generated by the fuzzer will be printed to the screen.
    var printNextGeneratedProgram: Bool
    
    init(for fuzzer: Fuzzer) {
        printNextGeneratedProgram = false
        
        // Event listeners etc. have to be registered on the fuzzer's queue
        fuzzer.sync {
            self.initOnFuzzerQueue(fuzzer)
            
        }
    }
    
    func initOnFuzzerQueue(_ fuzzer: Fuzzer) {
        // Register log event listener now to be able to print log messages
        // generated during fuzzer initialization
        fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
            let color = self.colorForLevel[ev.level]!
            if ev.origin == fuzzer.id {
                print("\u{001B}[0;\(color.rawValue)m[\(ev.label)] \(ev.message)\u{001B}[0;\(Color.reset.rawValue)m")
            } else {
                // Mark message as coming from a worker by including its id
                let shortId = ev.origin.uuidString.split(separator: "-")[0]
                print("\u{001B}[0;\(color.rawValue)m[\(shortId):\(ev.label)] \(ev.message)\u{001B}[0;\(Color.reset.rawValue)m")
            }
        }
        
        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { crash in
            if crash.isUnique {
                print("########## Unique Crash Found ##########")
                print(fuzzer.lifter.lift(crash.program, withOptions: .includeComments))
            }
        }
        
        fuzzer.registerEventListener(for: fuzzer.events.ProgramGenerated) { program in
            if self.printNextGeneratedProgram {
                print("--------- Generated Program -----------")
                print(fuzzer.lifter.lift(program, withOptions: [.dumpTypes]))
                self.printNextGeneratedProgram = false
            }
        }
        
        // Do everything else after fuzzer initialization finished
        fuzzer.registerEventListener(for: fuzzer.events.Initialized) {
            if let stats = Statistics.instance(for: fuzzer) {
                fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
                    print("\n++++++++++ Fuzzer Finished ++++++++++\n")
                    self.printStats(stats.compute(), of: fuzzer)
                }
                
                // We could also run our own timer on the main queue instead if we want to
                fuzzer.timers.scheduleTask(every: 60 * Seconds) {
                    self.printStats(stats.compute(), of: fuzzer)
                    print()
                }
            }
        }
    }
    
    func printStats(_ stats: Fuzzilli_Protobuf_Statistics, of fuzzer: Fuzzer) {
        var interestingSamplesInfo = "Interesting Samples Found:    \(stats.interestingSamples)"
        if fuzzer.config.collectRuntimeTypes {
            interestingSamplesInfo += " (\(String(format: "%.2f%%", stats.interestingSamplesWithTypesRate * 100)) with runtime type information)"
        }

        var phase: String
        switch fuzzer.phase {
        case .corpusImport:
            phase = "Corput import"
        case .initialCorpusGeneration:
            phase = "Initial corpus generation (with \(fuzzer.engine.name))"
        case .fuzzing:
            phase = "Fuzzing (with \(fuzzer.engine.name))"
        }

        print("""
        Fuzzer Statistics
        -----------------
        Fuzzer phase:                 \(phase)
        Total Samples:                \(stats.totalSamples)
        \(interestingSamplesInfo)
        Valid Samples Found:          \(stats.validSamples)
        Corpus Size:                  \(fuzzer.corpus.size)
        Correctness Rate:             \(String(format: "%.2f%%", stats.successRate * 100))
        Timeout Rate:                 \(String(format: "%.2f%%", stats.timeoutRate * 100))
        Crashes Found:                \(stats.crashingSamples)
        Timeouts Hit:                 \(stats.timedOutSamples)
        Coverage:                     \(String(format: "%.2f%%", stats.coverage * 100))
        Avg. program size:            \(String(format: "%.2f", stats.avgProgramSize))
        Connected workers:            \(stats.numWorkers)
        Execs / Second:               \(String(format: "%.2f", stats.execsPerSecond))
        Fuzzer Overhead:              \(String(format: "%.2f", stats.fuzzerOverhead * 100))%
        Total Execs:                  \(stats.totalExecs)
        """)

        if fuzzer.config.collectRuntimeTypes {
            print("""
            Type collection timeout rate: \(String(format: "%.2f%%", stats.typeCollectionTimeoutRate * 100))
            Type collection failure rate: \(String(format: "%.2f%%", stats.typeCollectionFailureRate * 100))
            """)
        }
    }
    
    private enum Color: Int {
        case reset   = 0
        case black   = 30
        case red     = 31
        case green   = 32
        case yellow  = 33
        case blue    = 34
        case magenta = 35
        case cyan    = 36
        case white   = 37
    }
    
    // The color with which to print log entries.
    private let colorForLevel: [LogLevel: Color] = [
        .verbose: .cyan,
        .info:    .white,
        .warning: .yellow,
        .error:   .magenta,
        .fatal:   .red
    ]
}
