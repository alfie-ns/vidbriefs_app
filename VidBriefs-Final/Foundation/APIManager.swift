//
//  APIManager.swift
//  Youtube-Summarizer
//
//  Created by Alfie Nurse on 02/09/2023.
//

import Foundation
import KeychainSwift



struct APIManager {
    
    private static var keychain = KeychainSwift()
    static var openai_apikey: String {
        keychain.get("openai-apikey") ?? ""
    }
    //let openai_apikey = APIManager.openai_apikey
    
    let openai_apikey = "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"
    
    
    
    // Structures
    
    // Structure to store and manage request timestamps to allow less than 3 requests a month
    struct RequestTracker {
        static var timestamps: [Date] = []

        static func cleanUpOldTimestamps() {
            timestamps = timestamps.filter { Date().timeIntervalSince($0) < 604800 } // 604800 seconds in a week
        }

        static func isRequestAllowed() -> Bool {
            cleanUpOldTimestamps()
            return timestamps.count < 3
        }

        static func addTimestamp() {
            timestamps.append(Date())
        }
    }
    
    // Defines a structure for decoding JSON responses related to video transcripts.
    struct TranscriptResponse: Decodable {
        let title: String       // Holds the title of the video.
        let transcript: String  // Contains the transcript text of the video.
    }

    // Defines a structure for decoding JSON responses related to video captions.
    struct CaptionResponse: Decodable {
        let kind: String        // Specifies the type of the response.
        let items: [Item]       // An array of 'Item' structures representing individual captions.
    }

    // Represents an individual caption item in the caption response.
    struct Item: Decodable {
        let id: String          // Unique identifier for the caption item.
    }

    // Defines a structure for holding snippet information of a video.
    struct Snippet: Decodable {
        let videoId: String     // The unique identifier of the video associated with this snippet.
    }
    
    func retrieveOpenAIKey() -> String? {
        return ProcessInfo.processInfo.environment["openai-apikey"]
    }
    
    

    
    
        // Custom insight function
        static func handleCustomInsightAll(yt_url: String, userPrompt: String, completion: @escaping (Bool, String?) -> Void) {
                    
            // Step 1: Get the entire transcript
            
            // Call gettranscript function and pass the url entered by the user as "transcript" parameter
            GetTranscript(yt_url: yt_url) { (success, transcript) in
                if success, let transcript = transcript { // If successful API call transcriptt = the transcript got
                    print("Transcript from youtube: \(transcript)") // Verify transcript fetched by displaying it
                    
                    let words = transcript.split(separator: " ")
                    print("Words in transcript: \(words.count)")
                    
                    if words.count < 85000 {
                        print("Not too much tokens to read in one prompt")
                        
                        fetchOneGPTSummary(transcript: transcript, customInsight: userPrompt) { finalSummary in
                            if let finalSummary = finalSummary {
                                completion(true, finalSummary)
                            }
                            else {
                                completion(false, "GPT could not be reached, check the API key is correct")
                            }
                        }

                    }
                    else if words.count > 85000 {
                        let chunks = breakIntoChunks(transcript: transcript) // Call breakIntoChunks and pass the transcript
                        fetchGPTSummaries(chunks: chunks, customInsight: userPrompt) { (finalSummary) in
                            if let finalSummary = finalSummary {
                                completion(true, finalSummary)
                            }
                            else {
                                completion(false, "GPT could not be reached, check the API key is correct")
                            }
                        }
                    }
                    else {
                        print("Error")
                    }
                    
                    // Step 2: Break the transcript into chunks
                    
                    // Step 3: Call fetchGPTSummaries with all chunks
                    
                } else {
                    completion(false, "Could not get the transcript, check the url is correct")
                }
            }
        }
    
    static func fetchOneGPTSummary(transcript: String, customInsight: String, completion: @escaping (String?) -> Void)
    {
        let apiUrl = URL(string: "https://api.openai.com/v1/chat/completions")! // OpenAI API url
        let dispatchGroup = DispatchGroup()
        
        dispatchGroup.enter() // enter dispatch group
        
        // Create request to OpenAI
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST" // POST request
        request.addValue("Bearer \(openai_apikey)", forHTTPHeaderField: "Authorization") // User users API key as http header
        request.addValue("application/json", forHTTPHeaderField: "Content-Type") //
        request.timeoutInterval = 300.0 // Long interval to prevent long response timeout
        
        // Construct the body of the request with the task and the summaries
        let requestBody: [String: Any] = [
            
            "model": "gpt-4-1106-preview", // Specify the model to use
            "messages": [["role": "system", "content": """

              Your task is to summarise the this text:{\(transcript)}, and
              answer the users question: \(customInsight)
            
            
            """]]
            
            ]// Provides the context and the task for the model
            
            // Attempt to serialize the request body to JSON
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            } catch {
                print("Failed to serialize JSON for final summary") // Log serialization error
                completion(nil) // Complete with nil due to error
                return
            }
            
            // Perform the network task to get the final summary
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                do {
                    // Attempt to deserialize the JSON response
                    if let json = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any] {
                        // Extract the summary text from the JSON response
                        if let choices = json["choices"] as? [[String: Any]],
                           let message = choices.first?["message"] as? [String: Any],
                           let text = message["content"] as? String {
                            completion(text) // Pass the final summary to the completion handler
                        } else {
                            print("Failed to extract final summary text.") // Log an error if the summary text is not found
                            completion(nil) // Complete with nil due to error
                        }
                    } else {
                        print("Failed to cast JSON for final summary.") // Log an error if JSON casting fails
                        completion(nil) // Complete with nil due to error
                    }
                } catch let jsonError {
                    print("Failed to parse JSON for final summary due to error: \(jsonError)") // Log JSON parsing error
                    completion(nil) // Complete with nil due to error
                }
            }
            task.resume() // Start the network task
    }
    
    
    
    
    
    
    
    
    
    
    static func fetchGPTSummaries(chunks: [String], customInsight: String, completion: @escaping (String?) -> Void) {
        
        let apiUrl = URL(string: "https://api.openai.com/v1/chat/completions")! // OpenAI API url
        var summaries: [String] = [] // Summary list created for each seperate summary
        let dispatchGroup = DispatchGroup() // Create a new DispatchGroup to manage a set of related, asynchronous tasks.
        
        

        print("Before fetchGPTSummaries for loop")
        
        for (index, chunk) in chunks.enumerated() { // For each index(to count the chunks) and chunk
            dispatchGroup.enter() // Enter DispatchGroup
            print("Entered Dispatch Group for chunk \(index + 1)") // Log numbered interation of the loop
//          let openai_apikey = UserDefaults.standard.string(forKey: "openai_apikey") ?? "" // Use users API key
            
            // Create request to OpenAI
            var request = URLRequest(url: apiUrl)
            request.httpMethod = "POST" // POST request
            request.addValue("Bearer \(openai_apikey)", forHTTPHeaderField: "Authorization") // User users API key as http header
            request.addValue("application/json", forHTTPHeaderField: "Content-Type") //
            request.timeoutInterval = 300.0 // Long interval to prevent long response timeout
            
            // Create list called systemMessages with each necessary system message for the iterated GPT call
            var systemMessages: [[String: String]] = [
                
                ["role": "system", "content": String(format: "Start of loop %d", index + 1)],
                ["role": "system", "content": """
                
                    You are an AI personal assistant who has been asked to extract specific information from a YouTube video transcript.
                    The transcript has been divided into multiple chunks, and you must process each chunk individually.
                
                    Your task is to follow these steps:
                    - Review each chunk of the transcript and identify every piece of information that aligns with the given user prompt.
                    - After processing all chunks, summarize all the relevant pieces of information you have found in a single response.
                    - Only use information found in this transcript for your response.
                
                    
                    Your guiding rule, as defined by the user, is: \(customInsight)
                
                """],
                
                ["role": "system", "content": String(format: """
                
                    You are iterating over each chunk of a single entire YouTube video transcript,
                    you are interpreting chunk %d out of %d chunks of the entire video.
                    You must give notes about this chunk in regard to the user's prompt: (%@).
                    The next message contains the chunk content.
                
                """, index + 1, chunks.count, customInsight)],
                ["role": "system", "content": String(format: "CHUNK %d: %@", index + 1, chunk)],
                ["role": "system", "content": String(format: "End of loop %d", index + 1)]
                
            ]
            
            
            
            // Checks for last chunk
            if index == chunks.count - 1 {
                systemMessages.append(["role": "system", "content": "This is the final chunk of the entire video transcript. Please identify the last few sentences relative to all of the chunks if needed."]) // Append warning that final loop is now
            }
            
            // Request Body for OpenAI API call
            let requestBody: [String: Any] = [
                
                "model": "gpt-4-1106-preview", // MAY CHANGE THIS TO OPTION TO CHANGE TO 3.5
                "messages": systemMessages // Pass systemMessages list as messages for API call
            ]
            
            // Try serialize JSON and if faild catch print that
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            } catch {
                print("Failed to serialize JSON")
                completion(nil)
                return
            }
            // Attempt final stage of API call and check for 401 error
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                // Check for HTTP response and handle 401 Unauthorized error
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    print("Unauthorized: Invalid OpenAI API key.") // Log unauthorized access
                    completion(nil) // Complete with nil due to error
                    dispatchGroup.leave() // Signal that this async task is done
                    return
                }

                // Log the full API response for debugging
                print("API Response: \(String(describing: response))")
                // Attempt to convert data to a UTF-8 string and log it
                if let unwrappedData = data, let dataString = String(data: unwrappedData, encoding: .utf8) {
                    print("API Data String: \(dataString)")
                }

                // Attempt to parse the JSON data returned from the API
                do {
                    // Deserialize JSON into a dictionary and check for expected structure
                    if let unwrappedData = data, let json = try JSONSerialization.jsonObject(with: unwrappedData, options: []) as? [String: Any] {
                        print("Parsed JSON: \(json)") // Log the parsed JSON
                        // Navigate through the JSON structure to extract the summary text
                        if let choices = json["choices"] as? [[String: Any]],
                           let message = choices.first?["message"] as? [String: Any],
                           let text = message["content"] as? String {
                            summaries.append(text) // Append the summary text to summaries array
                        } else {
                            // Log an error if the expected summary text structure is not found
                            print("Failed to extract summary text for chunk \(index + 1)")
                        }
                    } else {
                        // Log an error if JSON data could not be cast to a dictionary
                        print("Failed to cast JSON for chunk \(index + 1)")
                    }
                } catch let jsonError {
                    // Log parsing error details
                    print("Failed to parse JSON for chunk \(index + 1) due to error: \(jsonError)")
                }
                // Indicate that this part of the task is complete
                dispatchGroup.leave()
            }
            // Start the network task
            task.resume()
        }
        
        // SECOND OPENAI CALL TO SUMMARIZE SUMMARISED CHUNKS
            
            // After all tasks in the dispatch group have completed, this block will be executed
            dispatchGroup.notify(queue: .main) {
                let intermediateSummary = summaries.joined(separator: "\n") // Combine all summaries into one string
                var request = URLRequest(url: apiUrl) // Prepare a new URLRequest for the OpenAI API
                request.httpMethod = "POST" // Set the HTTP method to POST
                request.addValue("Bearer \(openai_apikey)", forHTTPHeaderField: "Authorization") // Include the API key in the request headers
                request.addValue("application/json", forHTTPHeaderField: "Content-Type") // Set the content type of the request to JSON
                request.timeoutInterval = 300.0 // Set a timeout interval of 5 minutes
                
                // Construct the body of the request with the task and the summaries
                let requestBody: [String: Any] = [
                    
                    "model": "gpt-4-1106-preview", // Specify the model to use
                    "messages": [["role": "system", "content": """
                                
                                  Your task is now to summarize all the relevant pieces
                                  of information you have found in a single response.
                                
                                  Listed summary information: \(intermediateSummary)
                                  Users prompt: \(customInsight)
                                
                                """]] // Provides the context and the task for the model
                ]
                
                // Attempt to serialize the request body to JSON
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
                } catch {
                    print("Failed to serialize JSON for final summary") // Log serialization error
                    completion(nil) // Complete with nil due to error
                    return
                }
                
                // Perform the network task to get the final summary
                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    do {
                        // Attempt to deserialize the JSON response
                        if let json = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any] {
                            // Extract the summary text from the JSON response
                            if let choices = json["choices"] as? [[String: Any]],
                               let message = choices.first?["message"] as? [String: Any],
                               let text = message["content"] as? String {
                                completion(text) // Pass the final summary to the completion handler
                            } else {
                                print("Failed to extract final summary text.") // Log an error if the summary text is not found
                                completion(nil) // Complete with nil due to error
                            }
                        } else {
                            print("Failed to cast JSON for final summary.") // Log an error if JSON casting fails
                            completion(nil) // Complete with nil due to error
                        }
                    } catch let jsonError {
                        print("Failed to parse JSON for final summary due to error: \(jsonError)") // Log JSON parsing error
                        completion(nil) // Complete with nil due to error
                    }
                }
                task.resume() // Start the network task
            }
        }

    
    // GET TRANSCRIPT API CALL
    static func GetTranscript(yt_url: String, completion: @escaping (Bool, String?) -> Void) {
        
        //let getTranscriptUrl = URL(string: "http://127.0.0.1:8000/response/get_youtube_transcript/")!
        let getTranscriptUrl = URL(string: "http://34.125.254.213:8000/response/get_youtube_transcript/")!
        
        // Makes request to the api for youtube transcript
        var request = URLRequest(url: getTranscriptUrl)
        request.httpMethod = "POST"
        request.timeoutInterval = 3000
        
        // Give the youtube url to my api as a parameter in the api call
        let parameters: [String: Any] = [
            "url": yt_url
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Initiates a URLSession data task with the given request. Upon completion,
        // it checks for a valid HTTPURLResponse and passes a failure message if not received.
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, "Fetch failed.")
                return
            }
            
            // Switch between each case
            switch httpResponse.statusCode {
            case 200...299: // Status codes indicating success
                // If data = the data given back by the API call
                if let data = data {
                    
                    do { // Do the following
                        // Decode the data received from API and save as decodedData
                        let decodedData = try JSONDecoder().decode([String: String].self, from: data)
                        // If can decode response data, save to responseString
                        if let responseString = decodedData["response"] {
                            // API call completed successfully, return the response string
                            completion(true, responseString)
                        } else {
                            // Key 'response' not found in decoded data, return an error
                            completion(false, "Key not found.")
                        }
                    } catch { // Catch and handle errors in decoding
                        // Decoding the JSON failed, return an error
                        completion(false, "Decoding failed.")
                    }
                } else {
                    // No data was returned by the API call, return an error
                    completion(false, "No data.")
                }
            default: // Any other status codes indicate a failed fetch
                // The fetch did not succeed, return an error
                completion(false, "Fetch failed with status code: \(httpResponse.statusCode).")
            }
        }.resume() // Resume the task if it's in a suspended state; this starts the network call
    }
    
    // BREAK TRANSCRIPT INTO CHUNKS
    static func breakIntoChunks(transcript: String, maxTokens: Int = 80000) -> [String] {
        var chunks: [String] = [] // Holds the chunks of transcript text
        let words = transcript.split(separator: " ") // Splits transcript into words
        var chunk: [String] = [] // Temp storage for the current chunk
        var tokenCount: Int = 0 // Tracks the number of tokens in the current chunk

        // Loop through each word in the transcript
        for word in words {
            let currentWordTokenCount = 1 // Pretend each word counts as one token
            // Check if adding the current word keeps us under the max token limit
            if tokenCount + currentWordTokenCount <= maxTokens {
                chunk.append(String(word)) // Add word to current chunk
                tokenCount += currentWordTokenCount // Update token count
            } else {
                chunks.append(chunk.joined(separator: " ")) // Chunk's full, add it to chunks array
                chunk = [String(word)] // Start a new chunk with the current word
                tokenCount = currentWordTokenCount // Reset token count for new chunk
            }
        }
        
        // Catch any remaining words that didn't make the last full chunk
        if !chunk.isEmpty {
            chunks.append(chunk.joined(separator: " ")) // Add final chunk to chunks array
        }
        
        return chunks // Send back all the chunks made
    }

}


