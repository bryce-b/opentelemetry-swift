// Copyright 2020, OpenTelemetry Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import OpenTelemetryApi

/// Represents the shared state/config between all Tracers created by the same TracerProvider.
class TracerSharedState {
    var clock: Clock
    var idGenerator: IdGenerator
    var resource: Resource

    var activeSpanLimits: SpanLimits
    var sampler: Sampler
    var activeSpanProcessor: SpanProcessor
    var hasBeenShutdown = false
    var launchEnvironmentContext: SpanContext?

    var registeredSpanProcessors = [SpanProcessor]()

    init(clock: Clock,
         idGenerator: IdGenerator,
         resource: Resource,
         spanLimits: SpanLimits,
         sampler: Sampler,
         spanProcessors: [SpanProcessor])
    {
        self.clock = clock
        self.idGenerator = idGenerator
        self.resource = resource
        self.activeSpanLimits = spanLimits
        self.sampler = sampler
        if spanProcessors.count > 1 {
            self.activeSpanProcessor = MultiSpanProcessor(spanProcessors: spanProcessors)
            registeredSpanProcessors = spanProcessors
        } else if spanProcessors.count == 1 {
            self.activeSpanProcessor = spanProcessors[0]
            registeredSpanProcessors = spanProcessors
        } else {
            activeSpanProcessor = NoopSpanProcessor()
        }

        /// Recovers explicit parent context from process environment variables, it allows to automatic
        /// trace context propagation to child processes
        let environmentPropagator = EnvironmentContextPropagator()
        self.launchEnvironmentContext = environmentPropagator.extract(carrier: ProcessInfo.processInfo.environment, getter: EnvironmentGetter())
    }

    /// Adds a new SpanProcessor
    /// - Parameter spanProcessor:  the new SpanProcessor to be added.
    func addSpanProcessor(_ spanProcessor: SpanProcessor) {
        registeredSpanProcessors.append(spanProcessor)
        if registeredSpanProcessors.count > 1 {
            activeSpanProcessor = MultiSpanProcessor(spanProcessors: registeredSpanProcessors)
        } else {
            activeSpanProcessor = registeredSpanProcessors[0]
        }
    }

    /// Stops tracing, including shutting down processors and set to true isStopped.
    func stop() {
        if hasBeenShutdown {
            return
        }
        activeSpanProcessor.shutdown()
        hasBeenShutdown = true
    }

    func setActiveSpanLimits(_ activeSpanLimits: SpanLimits) {
        self.activeSpanLimits = activeSpanLimits
    }

    func setSampler(_ sampler: Sampler) {
        self.sampler = sampler
    }

    // Sets the global sampler probability
    func setSamplerProbability(samplerProbability: Double) {
        if samplerProbability >= 1 {
            return setSampler(Samplers.alwaysOn)
        } else if samplerProbability <= 0 {
            return setSampler(Samplers.alwaysOff)
        } else {
            return setSampler(Samplers.traceIdRatio(ratio: samplerProbability))
        }
    }

    private struct EnvironmentGetter: Getter {
        func get(carrier: [String: String], key: String) -> [String]? {
            if let value = carrier[key] {
                return [value]
            }
            return nil
        }
    }
}
